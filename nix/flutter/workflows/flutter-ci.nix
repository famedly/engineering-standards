{ config, lib, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
in
{
  perSystem = { config, ... }:
    lib.mkIf (config.famedly.standards.flutter.projects != { }) {
      githubActions.workflows.flutter-ci = {
        name = "Flutter CI";

        # Run on PRs and merge queue entries only — not on push, since
        # the start/end of the commit series isn't clear in that case.
        on.pullRequest = {
          branches = [ "**" ];
          types = [
            "opened"
            "reopened"
            "synchronize"
            "ready_for_review"
          ];
        };
        on.mergeGroup = { };

        concurrency = {
          group = "\${{ github.workflow }}-\${{ github.ref }}";
          cancelInProgress = true;
        };

        jobs.flutter = {
          runsOn = "ubuntu-latest";

          steps = [
            { uses = allowed-actions."actions/checkout".uses; }
            { uses = allowed-actions."cachix/install-nix-action".uses; }

            {
              name = "Check formatting";
              shell = "nix develop .#flutter --command bash {0}";
              run = "dart format lib/ --set-exit-if-changed";
            }
            {
              name = "Fetch dependencies";
              shell = "nix develop .#flutter --command bash {0}";
              run = "flutter pub get";
            }
            {
              name = "Run analyzer";
              shell = "nix develop .#flutter --command bash {0}";
              run = "flutter analyze";
            }
            {
              name = "Run dart_code_linter";
              shell = "nix develop .#flutter --command bash {0}";
              run = ''
                if grep -q 'dart_code_linter:' pubspec.yaml; then
                  dart run dart_code_linter:metrics analyze lib
                fi
              '';
            }
          ];
        };
      };
    };
}
