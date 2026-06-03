{ config, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
in
{
  perSystem =
    { ... }:
    {
      githubActions.workflows.dart-test = {
        name = "Dart test workflow";

        on = {
          push = {
            branches = [ "main" ];
            tags = [ "*" ];
          };

          pullRequest = {
            branches = [ "*" ];
            types = [
              "opened"
              "reopened"
              "synchronize"
              "ready_for_review"
            ];
          };
        };

        concurrency = {
          group = "\${{ github.workflow }}-\${{ github.ref }}";
          cancelInProgress = true;
        };

        defaults.run.shell = "nu --no-config-file --no-history {0}";
        env.DART_TERM_COLOR = "always";

        jobs.test = {
          runsOn = "ubuntu-latest-4core";

          steps = [
            { uses = allowed-actions."actions/checkout".uses; }
            { uses = allowed-actions."cachix/install-nix-action".uses; }
          ];
        };
      };
    };
}
