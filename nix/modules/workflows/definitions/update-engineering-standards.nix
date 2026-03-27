{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghSecret;

  ciCfg =
    if famedlyConfig.github.workflows ? ci then
      famedlyConfig.github.workflows.ci
    else
      { armRunners = false; };

  runsOn = if (ciCfg.armRunners or false) then "arm-ubuntu-latest-8core" else "ubuntu-latest";
in
{
  options.schedule = lib.mkOption {
    type = lib.types.str;
    default = "0 6 * * 1";
    description = "Cron schedule for the weekly update check (default: Monday 06:00 UTC).";
  };

  config.definition = {
    name = "Update engineering-standards";
    on = {
      repositoryDispatch.types = [ "engineering-standards-update" ];
      schedule = [ { cron = config.schedule; } ];
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
        { uses = "actions/checkout@${av.checkout}"; }
        {
          uses = "cachix/install-nix-action@${av.installNix}";
          with_.extra_nix_config = "experimental-features = nix-command flakes";
        }
        {
          uses = "cachix/cachix-action@${av.cachixAction}";
          with_ = {
            name = "famedly";
            signingKey = ghSecret "CACHIX_SIGNING_KEY_FAMEDLY";
            authToken = ghSecret "CACHIX_AUTH_TOKEN_FAMEDLY";
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
          env.GH_TOKEN = ghSecret "GITHUB_TOKEN";
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
}
