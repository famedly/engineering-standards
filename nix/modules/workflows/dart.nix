# Dart workflow module: generates caller workflows for Dart/Flutter CI and publishing.
#
# Generated files in consumer repo:
#   .github/workflows/dart-ci.yml       — Dart/Flutter CI pipeline
#   .github/workflows/publish-pub.yml   — publish to pub.dev
#   .github/workflows/review-app.yml    — deploy review app

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

      dartCiYaml =
        let
          hasWithInputs =
            cfg.dartCi.envFile != "" || cfg.dartCi.directory != "" || cfg.dartCi.ignoreFormatting != "";
          withSection =
            lib.optionalString hasWithInputs "    with:\n"
            + lib.optionalString (cfg.dartCi.envFile != "") "      env_file: ${cfg.dartCi.envFile}\n"
            + lib.optionalString (cfg.dartCi.directory != "") "      directory: ${cfg.dartCi.directory}\n"
            + lib.optionalString (
              cfg.dartCi.ignoreFormatting != ""
            ) "      ignore_formatting: ${cfg.dartCi.ignoreFormatting}\n";
        in
        pkgs.writeText "dart-ci.yml" ''
          # managed-by: engineering-standards — do not edit manually
          # Regenerate with: nix run .#regenerateStandards
          name: Dart CI
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
              uses: famedly/engineering-standards/.github/workflows/dart-ci.yml@${ref}
          ${withSection}
              secrets: inherit
        '';

      publishPubYaml =
        let
          withEnvFile = lib.optionalString (
            cfg.dartPublish.envFile != ""
          ) "    with:\n      env_file: ${cfg.dartPublish.envFile}";
        in
        pkgs.writeText "publish-pub.yml" ''
          # managed-by: engineering-standards — do not edit manually
          # Regenerate with: nix run .#regenerateStandards
          name: Publish to pub.dev
          on:
            push:
              tags: ["v*"]

          jobs:
            publish:
              uses: famedly/engineering-standards/.github/workflows/dart-publish-pub.yml@${ref}
          ${withEnvFile}
        '';

      reviewAppYaml = pkgs.writeText "review-app.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Deploy review app
        on:
          pull_request:
            types: [opened, reopened, synchronize, closed]

        jobs:
          review:
            uses: famedly/engineering-standards/.github/workflows/dart-review-app.yml@${ref}
            with:
              pr: ''${{ github.event.pull_request.number }}
              projectname: ${cfg.dartReviewApp.projectName}
              environment: ${cfg.dartReviewApp.environment}
            secrets: inherit
      '';
    in
    {
      options.famedly.standards.workflows = {
        dartCi = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate Dart/Flutter CI workflow.";
          };

          envFile = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Path to .env file for version overrides.";
          };

          directory = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Subdirectory for the dart project.";
          };

          ignoreFormatting = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Subdirectory to auto-format before the format check (e.g. lib/l10n/).";
          };
        };

        dartPublish = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate pub.dev publish workflow.";
          };

          envFile = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Path to .env file for version overrides.";
          };
        };

        dartReviewApp = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate review app deployment workflow.";
          };

          projectName = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Project name used in the review app URL.";
          };

          environment = lib.mkOption {
            type = lib.types.str;
            default = "review";
            description = "GitHub environment name for the deployment.";
          };
        };
      };

      config = {
        famedly.standards._internal.managedFiles =
          lib.optionals cfg.dartCi.enable [
            {
              src = dartCiYaml;
              dest = ".github/workflows/dart-ci.yml";
            }
          ]
          ++ lib.optionals cfg.dartPublish.enable [
            {
              src = publishPubYaml;
              dest = ".github/workflows/publish-pub.yml";
            }
          ]
          ++ lib.optionals cfg.dartReviewApp.enable [
            {
              src = reviewAppYaml;
              dest = ".github/workflows/review-app.yml";
            }
          ];
      };
    }
  );
}
