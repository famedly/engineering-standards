# CI Workflow module: generates a complete .github/workflows/ci.yml.
#
# The CI workflow is just a Nix runner — all build/test/lint logic lives
# in `nix flake check`.
#
# The generated ci.yml:
#   1. Checks out the repo
#   2. Installs Nix
#   3. Sets up Cachix
#   4. Runs `nix flake check`

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
      cfg = config.famedly.standards.ci;
      av = config.famedly.standards.actionVersions;
      pinData = import ../action-versions-data.nix;

      runsOn = if cfg.armRunners then "arm-ubuntu-latest-8core" else "ubuntu-latest";
    in
    {
      options.famedly.standards.ci = {
        enable = lib.mkEnableOption "generate standard CI workflow";

        armRunners = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Use Famedly ARM runners instead of standard ubuntu-latest.";
        };
      };

      config = lib.mkIf cfg.enable {
        githubActions.workflows.ci = {
          name = "CI";
          on = {
            push = {
              branches = [ "main" ];
              tags = [ "*" ];
            };
            pullRequest = {
              branches = [ "**" ];
              types = [
                "opened"
                "reopened"
                "synchronize"
                "ready_for_review"
              ];
            };
            mergeGroup = { };
          };
          concurrency = {
            group = "\${{ github.workflow }}-\${{ github.ref }}";
            cancelInProgress = true;
          };
          jobs.nix-checks = {
            name = "Nix checks";
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
                name = "Run all checks";
                run = "nix flake check -L";
              }
            ];
          };
        };

        famedly.standards._internal.managedFiles = [
          {
            src = config.githubActions.workflowFiles."ci.yml";
            dest = ".github/workflows/ci.yml";
          }
        ];
      };
    }
  );
}
