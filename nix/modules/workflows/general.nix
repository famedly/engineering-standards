# General workflow module: generates caller workflows for shared checks.
#
# Generated files in consumer repo:
#   .github/workflows/general-checks.yml          — conventional commit validation
#   .github/workflows/authenticate-commits.yml     — OpenPGP commit authentication
#   .github/workflows/add-to-project.yml           — auto-add issues to project board
#   .github/workflows/update-openpgp-policy.yml    — regenerate openpgp-policy.toml
#   .github/workflows/fast-forward.yml             — fast-forward merge via PR comment

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

      conventionalCommitsYaml = pkgs.writeText "general-checks.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: General checks
        on:
          pull_request:
            branches: ["**"]
            types: [opened, reopened, synchronize]

        concurrency:
          group: ''${{ github.workflow }}-''${{ github.ref }}
          cancel-in-progress: true

        jobs:
          checks:
            uses: famedly/engineering-standards/.github/workflows/general-checks.yml@${ref}
      '';

      authenticateCommitsYaml = pkgs.writeText "authenticate-commits.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Authenticate commits
        on:
          pull_request:
            types: [opened, reopened, synchronize]

        concurrency:
          group: ''${{ github.workflow }}-''${{ github.ref }}
          cancel-in-progress: true

        jobs:
          authenticate:
            uses: famedly/engineering-standards/.github/workflows/general-authenticate-commits.yml@${ref}
      '';

      addToProjectYaml = pkgs.writeText "add-to-project.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Add to project
        on:
          issues:
            types: [opened]

        jobs:
          add:
            uses: famedly/engineering-standards/.github/workflows/general-add-to-project.yml@${ref}
            with:
              project-url: ${cfg.addToProject.projectUrl}
            secrets: inherit
      '';

      updateOpenpgpPolicyYaml = pkgs.writeText "update-openpgp-policy.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Update OpenPGP policy
        on:
          schedule:
            - cron: "0 6 * * 1"
          workflow_dispatch:

        jobs:
          update:
            uses: famedly/engineering-standards/.github/workflows/general-update-openpgp-policy.yml@${ref}
            with:
              teams: '${cfg.updateOpenpgpPolicy.teams}'
      '';

      fastForwardYaml = pkgs.writeText "fast-forward.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Fast-forward merge
        on:
          issue_comment:
            types: [created]

        jobs:
          fast-forward:
            uses: famedly/engineering-standards/.github/workflows/infra-fast-forward.yml@${ref}
            permissions:
              contents: write
              pull-requests: write
      '';

      aiReviewYaml = pkgs.writeText "ai-review.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: AI Code Review
        on:
          pull_request:
            branches: ["**"]
            types: [opened, reopened, synchronize, ready_for_review]

        concurrency:
          group: ''${{ github.workflow }}-''${{ github.ref }}
          cancel-in-progress: true

        jobs:
          review:
            uses: famedly/engineering-standards/.github/workflows/general-ai-review.yml@${ref}
        ${lib.optionalString (cfg.aiReview.model != "") "    with:\n      model: ${cfg.aiReview.model}"}
            secrets: inherit
      '';

      releaseYaml = pkgs.writeText "release.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Release
        on:
          push:
            tags:
              - "v*"

        jobs:
          release:
            uses: famedly/engineering-standards/.github/workflows/general-release.yml@${ref}
        ${lib.optionalString cfg.release.draft "    with:\n      draft: true"}
            secrets: inherit
      '';

      reuseYaml = pkgs.writeText "reuse.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: REUSE compliance
        on:
          pull_request:
            branches: ["**"]
            types: [opened, reopened, synchronize]

        concurrency:
          group: ''${{ github.workflow }}-''${{ github.ref }}
          cancel-in-progress: true

        jobs:
          reuse:
            uses: famedly/engineering-standards/.github/workflows/general-reuse.yml@${ref}
      '';
    in
    {
      options.famedly.standards.workflows = {
        conventionalCommits = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate workflow for conventional commit validation on PRs.";
        };

        authenticateCommits = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate workflow for OpenPGP commit authentication.";
        };

        fastForward = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate workflow for fast-forward merges via /fast-forward PR comment.";
        };

        addToProject = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate workflow to auto-add issues to a GitHub project.";
          };

          projectUrl = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "URL of the GitHub project board.";
            example = "https://github.com/orgs/famedly/projects/42";
          };
        };

        updateOpenpgpPolicy = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate workflow to regenerate openpgp-policy.toml.";
          };

          teams = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Teams input for the OpenPGP policy workflow (JSON array).";
            example = ''["backend", "frontend"]'';
          };
        };

        aiReview = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate AI code review workflow using anthropics/claude-code-action on PRs.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Claude model to use. Defaults to the workflow default (claude-sonnet-4-5).";
            example = "claude-opus-4-5";
          };
        };

        release = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate GitHub Release workflow triggered on version tag pushes.";
          };

          draft = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Create releases as drafts instead of publishing immediately.";
          };
        };

        reuse = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate REUSE/SPDX license compliance check workflow on PRs.";
        };
      };

      config = {
        famedly.standards._internal.managedFiles =
          lib.optionals cfg.conventionalCommits [
            {
              src = conventionalCommitsYaml;
              dest = ".github/workflows/general-checks.yml";
            }
          ]
          ++ lib.optionals cfg.authenticateCommits [
            {
              src = authenticateCommitsYaml;
              dest = ".github/workflows/authenticate-commits.yml";
            }
          ]
          ++ lib.optionals cfg.fastForward [
            {
              src = fastForwardYaml;
              dest = ".github/workflows/fast-forward.yml";
            }
          ]
          ++ lib.optionals cfg.addToProject.enable [
            {
              src = addToProjectYaml;
              dest = ".github/workflows/add-to-project.yml";
            }
          ]
          ++ lib.optionals cfg.updateOpenpgpPolicy.enable [
            {
              src = updateOpenpgpPolicyYaml;
              dest = ".github/workflows/update-openpgp-policy.yml";
            }
          ]
          ++ lib.optionals cfg.aiReview.enable [
            {
              src = aiReviewYaml;
              dest = ".github/workflows/ai-review.yml";
            }
          ]
          ++ lib.optionals cfg.release.enable [
            {
              src = releaseYaml;
              dest = ".github/workflows/release.yml";
            }
          ]
          ++ lib.optionals cfg.reuse [
            {
              src = reuseYaml;
              dest = ".github/workflows/reuse.yml";
            }
          ];
      };
    }
  );
}
