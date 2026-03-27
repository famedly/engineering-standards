{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghSecret ciConcurrency;
in
{
  options.armRunners = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Use Famedly ARM runners instead of standard ubuntu-latest.";
  };

  config.definition = {
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
    concurrency = ciConcurrency;
    jobs.nix-checks = {
      name = "Nix checks";
      runsOn = if config.armRunners then "arm-ubuntu-latest-8core" else "ubuntu-latest";
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
          name = "Run all checks";
          run = "nix flake check -L";
        }
      ];
    };
  };
}
