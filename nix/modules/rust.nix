# Rust standards module: crane-based checks, packages, and dev shell.
#
# Provides a declarative interface for Rust projects. Instead of manually
# defining crane derivations in the project's flake.nix, enable this module
# and pass in craneLib + src. The module generates:
#
#   checks.clippy  — cargo clippy (all features, deny warnings)
#   checks.fmt     — cargo fmt
#   checks.tests   — cargo nextest (patchShebangs, full source)
#   checks.deny    — cargo deny (license/advisory audit)
#   packages.default — release binary
#   packages.docker  — Docker image (opt-in)
#   devShells.default — combined dev shell (famedly-standards + crane)
#
# Usage:
#   famedly.standards.rust = {
#     enable = true;
#     craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;
#     src = ./.;                        # or ./backend for monorepos
#   };

{ flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.rust;
    in
    {
      options.famedly.standards.rust = {
        enable = lib.mkEnableOption "Rust standards (crane-based checks, packages, dev shell)";

        craneLib = lib.mkOption {
          type = lib.types.raw;
          description = ''
            Crane library instance with toolchain override applied.
            Typically: (inputs.crane.mkLib pkgs).overrideToolchain toolchain
          '';
        };

        src = lib.mkOption {
          type = lib.types.path;
          description = ''
            Project source root. The module applies cleanCargoSource for
            compilation/linting and lib.cleanSource for tests internally.
          '';
        };

        openssl = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Include openssl, pkg-config, and set OPENSSL_NO_VENDOR.";
        };

        extraBuildInputs = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional buildInputs for crane derivations.";
        };

        extraNativeBuildInputs = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional nativeBuildInputs for crane derivations.";
        };

        cargoExtraArgs = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Additional cargo arguments passed to all crane derivations
            (buildDepsOnly, cargoClippy, cargoNextest, buildPackage).
            Useful for enabling specific features, e.g. "--features simple-client".
          '';
        };

        checks = {
          nextest = {
            enable = lib.mkEnableOption "cargo nextest" // {
              default = true;
            };
            extraArgs = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = ''
                Additional arguments for cargo nextest (e.g. filter expressions).
                Example: "-E 'not test(e2e)'" to exclude e2e tests from nix flake check.
              '';
            };
          };
          deny = {
            enable = lib.mkEnableOption "cargo deny audit" // {
              default = true;
            };
          };
        };

        package = {
          enable = lib.mkEnableOption "default release package" // {
            default = true;
          };
        };

        docker = {
          enable = lib.mkEnableOption "Docker image from default package";
          name = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Image name (defaults to the package pname).";
          };
          tag = lib.mkOption {
            type = lib.types.str;
            default = "latest";
            description = "Image tag.";
          };
        };

        devShell = {
          enable = lib.mkEnableOption "combined Rust dev shell as devShells.default" // {
            default = true;
          };
          extraPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Extra packages to include in the dev shell (e.g. pkgs.flutter for monorepos).";
          };
        };
      };

      config = lib.mkIf cfg.enable (
        let
          cleanSrc = cfg.craneLib.cleanCargoSource cfg.src;
          fullSrc = lib.cleanSource cfg.src;

          extraArgs = lib.concatStringsSep " " (
            lib.filter (s: s != "") [
              "--locked"
              cfg.cargoExtraArgs
            ]
          );

          commonArgs = {
            src = cleanSrc;
            strictDeps = true;
            cargoExtraArgs = extraArgs;
            nativeBuildInputs = lib.optionals cfg.openssl [ pkgs.pkg-config ] ++ cfg.extraNativeBuildInputs;
            buildInputs = lib.optionals cfg.openssl [ pkgs.openssl ] ++ cfg.extraBuildInputs;
          }
          // lib.optionalAttrs cfg.openssl {
            OPENSSL_NO_VENDOR = "1";
            LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.openssl ];
          };

          cargoArtifacts = cfg.craneLib.buildDepsOnly commonArgs;

          defaultPkg = cfg.craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });
        in
        {
          checks =
            lib.optionalAttrs cfg.checks.nextest.enable {
              tests = cfg.craneLib.cargoNextest (
                commonArgs
                // {
                  inherit cargoArtifacts;
                  src = fullSrc;
                  preBuild = ''
                    find . -name '*.sh' -exec chmod +x {} \;
                    patchShebangs .
                  '';
                }
                // lib.optionalAttrs (cfg.checks.nextest.extraArgs != "") {
                  cargoNextestExtraArgs = cfg.checks.nextest.extraArgs;
                }
              );
            }
            // lib.optionalAttrs cfg.checks.deny.enable { deny = cfg.craneLib.cargoDeny { src = cleanSrc; }; };

          packages =
            lib.optionalAttrs cfg.package.enable { default = defaultPkg; }
            // lib.optionalAttrs (cfg.docker.enable && cfg.package.enable) {
              docker = pkgs.dockerTools.buildLayeredImage {
                name = if cfg.docker.name != "" then cfg.docker.name else defaultPkg.pname or "app";
                tag = cfg.docker.tag;
                contents = [
                  defaultPkg
                  pkgs.cacert
                ];
                config.Cmd = [ (lib.getExe defaultPkg) ];
              };
            };

          devShells = lib.optionalAttrs cfg.devShell.enable {
            default = pkgs.mkShell {
              inputsFrom =
                lib.optionals (
                  (config.famedly.standards.devShell.enable or false) && config.devShells ? famedly-standards
                ) [ config.devShells.famedly-standards ]
                ++ [ (cfg.craneLib.devShell { }) ];
              packages = [
                pkgs.cargo-watch
                pkgs.cargo-edit
                pkgs.cargo-deny
              ]
              ++ cfg.devShell.extraPackages;
            };
          };
        }
      );
    }
  );
}
