# flake.nix template for Flutter + Rust monorepos.
# Copy this file to your repo root and adjust as needed.
#
# Expected directory structure:
#   ├── flake.nix           (this file)
#   ├── frontend/           (Flutter app)
#   │   ├── pubspec.yaml
#   │   ├── lib/
#   │   └── test/
#   └── backend/            (Rust service)
#       ├── Cargo.toml
#       └── src/
#
# The flake uses the projects abstraction to scope linting configs,
# Dependabot entries, and pre-commit hooks to their directories.
{
  description = "REPLACE_WITH_REPO_DESCRIPTION";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    engineering-standards.url = "github:famedly/engineering-standards";
    crane.url = "github:ipetkov/crane";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.engineering-standards.flakeModules.default ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          pkgs,
          lib,
          system,
          ...
        }:
        let
          toolchain = inputs.fenix.packages.${system}.stable.toolchain;
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;

          nightlyToolchain = inputs.fenix.packages.${system}.latest.toolchain;
          craneLibNightly = (inputs.crane.mkLib pkgs).overrideToolchain nightlyToolchain;

          rustSrc = craneLib.cleanCargoSource ./backend;
          commonArgs = {
            src = rustSrc;
            strictDeps = true;
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          famedly.standards = {
            rules.enable = false;
            preCommitHooks.enable = true;
            infrastructure = {
              editorconfig = true;
              dependabot = true;
            };
            devShell.enable = true;

            projects = {
              backend = {
                language = "rust";
                directory = "backend";
              };
              frontend = {
                language = "flutter";
                directory = "frontend";
              };
            };

            dart = {
              enable = true;
              flutter = true;
            };
          };

          famedly.github.workflows = {
            ci = {
              enable = true;
              armRunners = false;
            };
            "general-checks".enable = true;
            "authenticate-commits".enable = false;
            "ai-review".enable = false;
            # rust-ci expects Cargo at repo root; this layout uses backend/
            "rust-ci".enable = false;
            # dart-ci is auto-enabled by dart.enable; only directory needs overriding
            "dart-ci".directory = "frontend";
            # "publish-crate".enable = true;     # uncomment for crate publishing
            # "docker-backend" = {               # uncomment for Docker builds
            #   enable = true;
            #   targets = "backend-service";
            # };
            # "fast-forward".enable = true;      # uncomment for /fast-forward PR merges
          };

          # Rust-specific checks via crane.
          checks = {
            clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-features --all-targets -- --deny warnings";
              }
            );

            fmt = craneLibNightly.cargoFmt { src = rustSrc; };

            tests = craneLib.cargoNextest (commonArgs // { inherit cargoArtifacts; });

            deny = craneLib.cargoDeny { src = rustSrc; };
          };

          packages.default = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

          devShells.default = pkgs.mkShell {
            inputsFrom =
              lib.optionals (config.famedly.standards.devShell.enable && config.devShells ? famedly-standards) [
                config.devShells.famedly-standards
              ]
              ++ [ (craneLib.devShell { }) ];
            packages = [
              pkgs.flutter
              pkgs.cargo-watch
              pkgs.cargo-edit
              pkgs.cargo-deny
            ];
          };
        };
    };
}
