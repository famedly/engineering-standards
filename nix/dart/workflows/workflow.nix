{ config, lib, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
in
{
  perSystem =
    { config, ... }:
    let
      run-pre-commit = project: ''
        nix develop .#general --command sh -c ${lib.escapeShellArg "cd ${lib.escapeShellArg project} && prek run --all-files"}
      '';
      dart-project-steps = lib.mapAttrsToList (project: _: {
        name = "Run Dart pre-commit checks (${project})";
        run = run-pre-commit project;
      }) config.famedly.standards.dart.projects;
    in
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
          ] ++ dart-project-steps;
        };
      };
    };
}
