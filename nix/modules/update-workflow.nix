# Update workflow module: generates .github/workflows/update-engineering-standards.yml
#
# This workflow keeps consumer repos in sync with the latest
# engineering-standards. It is triggered:
#
#   1. By `repository_dispatch` (type: engineering-standards-update)
#   2. On a weekly schedule (Monday 06:00 UTC) as a safety net
#   3. Manually via `workflow_dispatch`
#
# The workflow runs:
#   nix flake update engineering-standards
#   nix run .#regenerateStandards
#
# and opens a PR with the resulting changes.

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
      cfg = config.famedly.standards.updateWorkflow;
      ciCfg = config.famedly.standards.ci;
      av = config.famedly.standards.actionVersions;

      runsOn = if ciCfg.armRunners then "arm-ubuntu-latest-8core" else "ubuntu-latest";

      prBody = builtins.toJSON ''
        ## Automated engineering-standards update

        This PR was created automatically. It includes:

        - Updated `flake.lock` (pinned to latest engineering-standards)
        - Regenerated managed files via `nix run .#regenerateStandards`

        ### Review checklist

        - [ ] CI passes
        - [ ] No unexpected file changes

        > Created by the `update-engineering-standards` workflow.
      '';
    in
    {
      options.famedly.standards.updateWorkflow = {
        enable = lib.mkEnableOption "generate the auto-update workflow for engineering-standards";

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "0 6 * * 1";
          description = "Cron schedule for the weekly update check (default: Monday 06:00 UTC).";
        };
      };

      config = lib.mkIf cfg.enable {
        githubActions.workflows.update-engineering-standards = {
          name = "Update engineering-standards";
          on = {
            repositoryDispatch = {
              types = [ "engineering-standards-update" ];
            };
            schedule = [
              { cron = cfg.schedule; }
            ];
            workflowDispatch = { };
          };
          permissions = {
            contents = "write";
            pull-requests = "write";
          };
          concurrency = {
            group = "engineering-standards-update";
            cancelInProgress = true;
          };
          jobs.update = {
            name = "Update engineering-standards";
            runsOn = runsOn;
            steps = [
              {
                uses = "actions/checkout@${av.checkout}";
              }
              {
                uses = "cachix/install-nix-action@${av.installNix}";
                with_ = {
                  extra_nix_config = "experimental-features = nix-command flakes";
                };
              }
              {
                uses = "cachix/cachix-action@${av.cachixAction}";
                with_ = {
                  name = "famedly";
                  signingKey = "\${{ secrets.CACHIX_SIGNING_KEY_FAMEDLY }}";
                  authToken = "\${{ secrets.CACHIX_AUTH_TOKEN_FAMEDLY }}";
                };
                continueOnError = true;
              }
              {
                name = "Update flake input";
                run = "nix flake update engineering-standards";
              }
              {
                name = "Regenerate managed files";
                run = "nix run .#regenerateStandards";
              }
              {
                name = "Create or update PR";
                env = {
                  GH_TOKEN = "\${{ secrets.GITHUB_TOKEN }}";
                };
                run = ''
                  if git diff --quiet && git diff --staged --quiet; then
                    echo "No changes detected, already up to date."
                    exit 0
                  fi

                  BRANCH="engineering-standards/auto-update"
                  git config user.name "github-actions[bot]"
                  git config user.email "github-actions[bot]@users.noreply.github.com"

                  git checkout -B "$BRANCH"
                  git add -A
                  git commit -m "chore: update engineering-standards"
                  git push -f origin "$BRANCH"

                  if ! gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number' | grep -q .; then
                    gh pr create \
                      --title "chore: update engineering-standards" \
                      --body "## Automated engineering-standards update

                  This PR was created automatically. It includes:

                  - Updated \`flake.lock\` (pinned to latest engineering-standards)
                  - Regenerated managed files via \`nix run .#regenerateStandards\`

                  ### Review checklist

                  - [ ] CI passes
                  - [ ] No unexpected file changes

                  > Created by the \`update-engineering-standards\` workflow."
                  fi
                '';
              }
            ];
          };
        };

        famedly.standards._internal.managedFiles = [
          {
            src = config.githubActions.workflowFiles."update-engineering-standards.yml";
            dest = ".github/workflows/update-engineering-standards.yml";
          }
        ];
      };
    }
  );
}
