# Pre-commit hooks module: uses git-hooks.nix for Nix-native hook management.
#
# Hooks run both locally (via `nix develop` shell hook) and in CI
# (via `nix flake check` which includes the pre-commit check derivation).
#
# Replaces the old hooks.nix + hooks/*.yaml approach with a single
# source of truth — every check is defined once and runs identically
# in development and CI.
#
# Supported hook groups:
#   Base    — BOM, case-conflicts, merge-conflicts, YAML/TOML/JSON, etc.
#   FOSS    — REUSE license compliance
#   Rust    — clippy, rustfmt, cargo lockfile
#   Dart    — dart format, dart analyze
#   Python  — ruff check, ruff format
#
# Monorepo projects (via famedly.standards.projects) automatically
# generate directory-scoped hooks.

{
  inputs,
  flake-parts-lib,
  ...
}:
_caller-args: {
  imports = [ inputs.git-hooks-nix.flakeModule ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.preCommitHooks = {
        enable = lib.mkEnableOption "Nix-native pre-commit hooks via git-hooks.nix";

        fossHooks = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable FOSS licensing hooks (REUSE compliance).";
          };

          copyright = lib.mkOption {
            type = lib.types.str;
            default = "Famedly GmbH";
            description = "Default copyright holder for SPDX headers (used by addLicenseHeaders app).";
          };

          license = lib.mkOption {
            type = lib.types.str;
            default = "AGPL-3.0-only";
            description = "Default SPDX license identifier for headers (used by addLicenseHeaders app).";
          };
        };

        rustHooks.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Rust hooks (clippy, rustfmt, cargo lockfile) at the repo root.";
        };

        dartHooks.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Dart hooks (dart format, dart analyze) at the repo root.";
        };

        pythonHooks.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Python hooks (ruff check, ruff format) at the repo root.";
        };
      };
    }
  );

  config.perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.preCommitHooks;
      projects = config.famedly.standards.projects or { };

      projectsWithHooks = lib.filterAttrs (_: p: p.hooks or true) projects;

      rustProjects = lib.filterAttrs (_: p: p.language == "rust") projectsWithHooks;
      dartProjects = lib.filterAttrs (
        _: p: p.language == "dart" || p.language == "flutter"
      ) projectsWithHooks;
      pythonProjects = lib.filterAttrs (_: p: p.language == "python") projectsWithHooks;

      dartSdk = config.packages.famedly-dart-sdk or pkgs.dart;
      dartBin = "${dartSdk}/bin/dart";

      rustToolchain = config.packages.famedly-rust-toolchain or null;
      hasRustToolchain = rustToolchain != null;
      rustHooksActive = cfg.rustHooks.enable || rustProjects != { };

      reuseToml = pkgs.writeText "REUSE.toml" ''
        version = 1

        [[annotations]]
        path = [".editorconfig", ".engineering-standards-manifest", ".github/**", ".cursor/rules/standards/**", "CLAUDE.md", "**.standards.yaml"]
        SPDX-FileCopyrightText = "${cfg.fossHooks.copyright}"
        SPDX-License-Identifier = "${cfg.fossHooks.license}"
      '';

      addLicenseHeadersScript = pkgs.writeShellApplication {
        name = "addLicenseHeaders";
        runtimeInputs = [
          pkgs.reuse
          pkgs.git
        ];
        text = ''
          echo "Downloading missing license texts..."
          reuse download --all 2>/dev/null || true
          echo "Adding SPDX headers: --copyright=${lib.escapeShellArg cfg.fossHooks.copyright} --license=${lib.escapeShellArg cfg.fossHooks.license}"
          git ls-files -z | while IFS= read -r -d "" f; do
            [ -f "$f" ] && printf '%s\0' "$f"
          done | xargs -0 reuse annotate \
            --copyright=${lib.escapeShellArg cfg.fossHooks.copyright} \
            --license=${lib.escapeShellArg cfg.fossHooks.license} \
            --skip-unrecognised
          echo "Done. Run 'reuse lint' to verify compliance."
        '';
      };

      mkSlug = dir: if dir == "" then "root" else lib.replaceStrings [ "/" ] [ "-" ] dir;

      scopedRustHooks = lib.concatMapAttrs (
        _: project:
        let
          slug = mkSlug project.directory;
          dir = project.directory;
          cdCmd = if dir == "" then "" else "cd ${dir} && ";
          filesAttr = lib.optionalAttrs (dir != "") { files = "^${dir}/"; };
        in
        {
          "clippy-${slug}" = {
            enable = true;
            name = "clippy (${if dir == "" then "root" else dir})";
            entry = "bash -c '${cdCmd}cargo clippy --workspace --all-targets -- -D warnings'";
            language = "system";
            types = [ "rust" ];
            pass_filenames = false;
          }
          // filesAttr;

          "rustfmt-${slug}" = {
            enable = true;
            name = "rustfmt (${if dir == "" then "root" else dir})";
            entry = "bash -c '${cdCmd}cargo fmt -- --check'";
            language = "system";
            types = [ "rust" ];
          }
          // filesAttr;

          "cargo-lock-${slug}" = {
            enable = true;
            name = "cargo lockfile (${if dir == "" then "root" else dir})";
            entry = "bash -c '${cdCmd}cargo check'";
            language = "system";
            types = [ "rust" ];
            pass_filenames = false;
          }
          // filesAttr;
        }
      ) rustProjects;

      scopedDartHooks = lib.concatMapAttrs (
        _: project:
        let
          slug = mkSlug project.directory;
          dir = project.directory;
          cdCmd = if dir == "" then "" else "cd ${dir} && ";
          filesAttr = lib.optionalAttrs (dir != "") { files = "^${dir}/"; };
        in
        {
          "dart-format-${slug}" = {
            enable = true;
            name = "dart format (${if dir == "" then "root" else dir})";
            entry = "bash -c '${cdCmd}${dartBin} format'";
            language = "system";
            types = [ "dart" ];
          }
          // filesAttr;

          "dart-analyze-${slug}" = {
            enable = true;
            name = "dart analyze (${if dir == "" then "root" else dir})";
            entry = "bash -c '${cdCmd}${dartBin} analyze --fatal-infos'";
            language = "system";
            types = [ "dart" ];
            pass_filenames = false;
          }
          // filesAttr;
        }
      ) dartProjects;

      scopedPythonHooks = lib.concatMapAttrs (
        _: project:
        let
          slug = mkSlug project.directory;
          dir = project.directory;
          cdCmd = if dir == "" then "" else "cd ${dir} && ";
          filesAttr = lib.optionalAttrs (dir != "") { files = "^${dir}/"; };
        in
        {
          "ruff-check-${slug}" = {
            enable = true;
            name = "ruff check (${if dir == "" then "root" else dir})";
            entry = "bash -c '${cdCmd}${lib.getExe pkgs.ruff} check --fix'";
            language = "system";
            types = [ "python" ];
          }
          // filesAttr;

          "ruff-format-${slug}" = {
            enable = true;
            name = "ruff format (${if dir == "" then "root" else dir})";
            entry = "bash -c '${cdCmd}${lib.getExe pkgs.ruff} format'";
            language = "system";
            types = [ "python" ];
          }
          // filesAttr;
        }
      ) pythonProjects;
    in
    lib.mkIf cfg.enable {
      apps = lib.mkIf cfg.fossHooks.enable {
        addLicenseHeaders = {
          type = "app";
          meta.description = "Add SPDX license headers to all git-tracked files";
          program = lib.getExe addLicenseHeadersScript;
        };
      };

      famedly.standards._internal.managedFiles = lib.optionals cfg.fossHooks.enable [
        {
          src = reuseToml;
          dest = "REUSE.toml";
          initialOnly = true;
        }
      ];

      pre-commit = {
        check.enable = true;

        settings.tools = lib.mkMerge [
          (lib.mkIf (cfg.dartHooks.enable || dartProjects != { }) {
            dart = lib.mkForce dartSdk;
          })
          (lib.mkIf (rustHooksActive && hasRustToolchain) {
            cargo = lib.mkDefault rustToolchain;
            clippy = lib.mkDefault rustToolchain;
            rustfmt = lib.mkDefault rustToolchain;
          })
        ];

        settings.hooks = lib.mkMerge (
          [
            # Base hooks — always enabled when preCommitHooks.enable = true
            {
              fix-byte-order-marker.enable = true;
              check-case-conflicts.enable = true;
              check-merge-conflicts.enable = true;
              check-symlinks.enable = true;
              check-yaml.enable = true;
              check-toml.enable = true;
              check-json.enable = true;
              end-of-file-fixer.enable = true;
              mixed-line-endings.enable = true;
              trim-trailing-whitespace.enable = true;
              typos.enable = true;
              nixfmt-rfc-style = {
                enable = true;
                name = "nixfmt";
                entry = "${lib.getExe pkgs.nixfmt}";
                language = "system";
                types = [ "nix" ];
              };
            }

            (lib.mkIf cfg.fossHooks.enable { reuse.enable = true; })

            # Root-level language hooks (using built-in git-hooks.nix definitions)
            (lib.mkIf cfg.rustHooks.enable {
              clippy = {
                enable = true;
                settings = {
                  denyWarnings = true;
                  extraArgs = lib.escapeShellArgs [
                    "--workspace"
                    "--all-targets"
                  ];
                };
              };
              rustfmt = {
                enable = true;
                settings.check = true;
              };
            })

            (lib.mkIf cfg.dartHooks.enable {
              dart-format = {
                enable = true;
                entry = lib.mkForce "${dartBin} format";
              };
              dart-analyze = {
                enable = true;
                entry = lib.mkForce "${dartBin} analyze --fatal-infos";
                pass_filenames = false;
              };
            })

            (lib.mkIf cfg.pythonHooks.enable {
              ruff-check = {
                enable = true;
                name = "ruff check";
                entry = "${lib.getExe pkgs.ruff} check --fix";
                language = "system";
                types = [ "python" ];
              };
              ruff-format = {
                enable = true;
                name = "ruff format";
                entry = "${lib.getExe pkgs.ruff} format";
                language = "system";
                types = [ "python" ];
              };
            })
          ]

          # Project-scoped hooks (monorepo support)
          ++ lib.optional (rustProjects != { }) scopedRustHooks
          ++ lib.optional (dartProjects != { }) scopedDartHooks
          ++ lib.optional (pythonProjects != { }) scopedPythonHooks
        );
      };
    };
}
