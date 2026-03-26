# Rust workflow module: generates caller workflows for Rust CI and crate publishing.
#
# Generated files in consumer repo:
#   .github/workflows/rust-ci.yml       — Clippy, tests, coverage
#   .github/workflows/publish-crate.yml — publish to crate registry on tag push

{ flake-parts-lib, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.workflows;
      ref = config.famedly.standards.workflowRef;

      rustCiYaml =
        let
          hasWithInputs =
            cfg.rustCi.runner != ""
            || cfg.rustCi.container != ""
            || cfg.rustCi.features != ""
            || !cfg.rustCi.coverage
            || !cfg.rustCi.typos
            || cfg.rustCi.cargoDeny;
          withSection =
            lib.optionalString hasWithInputs "    with:\n"
            + lib.optionalString (cfg.rustCi.runner != "") "      runner: ${cfg.rustCi.runner}\n"
            + lib.optionalString (cfg.rustCi.container != "") "      container: ${cfg.rustCi.container}\n"
            + lib.optionalString (cfg.rustCi.features != "") "      features: ${cfg.rustCi.features}\n"
            + lib.optionalString (!cfg.rustCi.coverage) "      coverage: false\n"
            + lib.optionalString (!cfg.rustCi.typos) "      typos: false\n"
            + lib.optionalString cfg.rustCi.cargoDeny "      cargo_deny: true\n";
        in
        pkgs.writeText "rust-ci.yml" ''
          # managed-by: engineering-standards — do not edit manually
          # Regenerate with: nix run .#regenerateStandards
          name: Rust CI
          on:
            push:
              branches: ["main"]
            pull_request:
              branches: ["**"]
              types: [opened, reopened, synchronize, ready_for_review]
            merge_group:

          concurrency:
            group: ''${{ github.workflow }}-''${{ github.ref }}
            cancel-in-progress: ''${{ github.ref != 'refs/heads/main' }}

          jobs:
            ci:
              uses: famedly/engineering-standards/.github/workflows/rust-ci.yml@${ref}
          ${withSection}
              secrets: inherit
        '';

      publishCrateYaml =
        let
          extraTagLines = lib.concatMapStrings (p: "      - \"${p}\"\n") cfg.rustPublish.extraTagPatterns;
          withPackages = lib.optionalString (
            cfg.rustPublish.packages != ""
          ) "    with:\n      packages: ${cfg.rustPublish.packages}";
        in
        pkgs.writeText "publish-crate.yml" ''
          # managed-by: engineering-standards — do not edit manually
          # Regenerate with: nix run .#regenerateStandards
          name: Publish crate
          on:
            push:
              tags:
                - "v[0-9]+.[0-9]+.[0-9]+"
                - "v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+"
          ${extraTagLines}
          jobs:
            publish:
              uses: famedly/engineering-standards/.github/workflows/rust-publish-crate.yml@${ref}
          ${withPackages}
              secrets: inherit
        '';
    in
    {
      options.famedly.standards.workflows = {
        rustCi = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate Rust CI workflow (Clippy, tests, coverage).";
          };

          runner = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Override the runner for Rust CI jobs.";
            example = "arm-ubuntu-latest-32core";
          };

          container = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Override the container image for Rust CI jobs.";
            example = "ghcr.io/famedly/rust-container:nightly-2025-10-27";
          };

          features = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Feature flags to pass to cargo commands (default: --all-features).";
            example = "--features feat-a,feat-b";
          };

          coverage = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable coverage job with llvm-cov + Codecov upload.";
          };

          typos = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable spell-check job with crate-ci/typos.";
          };

          cargoDeny = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable license/dependency audit job with cargo-deny.";
          };
        };

        rustPublish = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate crate publish workflow triggered on version tags.";
          };

          packages = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Space-separated list of packages to publish (for workspaces).";
          };

          extraTagPatterns = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional tag patterns to trigger publishing.";
            example = [ "[a-zA-Z-_]+v[0-9]+.[0-9]+.[0-9]+" ];
          };
        };
      };

      config = {
        famedly.standards._internal.managedFiles =
          lib.optionals cfg.rustCi.enable [
            {
              src = rustCiYaml;
              dest = ".github/workflows/rust-ci.yml";
            }
          ]
          ++ lib.optionals cfg.rustPublish.enable [
            {
              src = publishCrateYaml;
              dest = ".github/workflows/publish-crate.yml";
            }
          ];
      };
    }
  );
}
