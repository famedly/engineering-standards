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
  lib,
  flake-parts-lib,
  ...
}:
_caller-args: {
  imports = [ inputs.git-hooks-nix.flakeModule ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, lib, ... }:
    {
      options.famedly.standards.preCommitHooks = {
        enable = lib.mkEnableOption "Nix-native pre-commit hooks via git-hooks.nix";

        fossHooks.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable FOSS licensing hooks (REUSE compliance).";
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
            entry = "bash -c '${cdCmd}cargo +nightly fmt -- --check'";
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
            entry = "bash -c '${cdCmd}dart format'";
            language = "system";
            types = [ "dart" ];
          }
          // filesAttr;

          "dart-analyze-${slug}" = {
            enable = true;
            name = "dart analyze (${if dir == "" then "root" else dir})";
            entry = "bash -c '${cdCmd}dart analyze --fatal-infos'";
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
      pre-commit = {
        check.enable = true;

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
              dart-format.enable = true;
              dart-analyze.enable = true;
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
