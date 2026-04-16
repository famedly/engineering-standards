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
#   Dart    — dart format, dart analyze, import_sorter, commented-out code, dart_code_linter
#   Python  — ruff check, ruff format
#
# Monorepo projects (via famedly.standards.projects) automatically
# generate directory-scoped hooks.

{ inputs, flake-parts-lib, ... }@localFlake:
importingFlake: {
  imports = [
    inputs.git-hooks-nix.flakeModule

    (flake-parts-lib.importApply ./dart.nix localFlake)
    (flake-parts-lib.importApply ./rust.nix localFlake)
    (flake-parts-lib.importApply ./reuse.nix localFlake)
  ];

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
    in
    lib.mkIf cfg.enable {
      pre-commit = {
        check.enable = true;

        settings.hooks = {
          # Base hooks — always enabled when preCommitHooks.enable = true
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
          nixfmt.enable = true;

          # Python hooks
          ruff-check.enable = cfg.pythonHooks.enable;
          ruff-format.enable = cfg.pythonHooks.enable;
        };
      };
    };
}
