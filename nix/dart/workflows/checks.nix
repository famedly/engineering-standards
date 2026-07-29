{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (config.famedly.standards.ci) steps;
  inherit (import ../../lib/project-paths.nix { inherit lib; }) inProject suffix;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.checks = {
            analyze = lib.mkOption {
              description = ''
                Whether to run `dart analyze` against this project in CI.
              '';
              type = lib.types.bool;
              default = true;
            };

            testCommand = lib.mkOption {
              description = ''
                The command that runs this projects' tests in CI, or `null` to
                not run any.

                This is deliberately not defaulted to `dart test`, since test
                suites that need external services (databases, homeservers,
                ...) have to be wired up by the project itself.
              '';
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "dart test test/unit/";
            };

            privateDependencies = lib.mkOption {
              description = ''
                Whether this project depends on private famedly repositories,
                and therefore needs an SSH key to resolve its dependencies.

                See `famedly.standards.ci.steps.privateDependencies`.
              '';
              type = lib.types.bool;
              default = false;
            };
          };
        }
      );
    };
  });

  config.perSystem =
    { config, ... }:
    let
      projects = config.famedly.standards.dart.projects;
    in
    lib.mkIf (projects != { }) {
      githubActions.workflows.dart-checks = {
        name = "Dart checks";

        # Mirrors `check-pre-commit-hooks`: on `push` the start and end of the
        # commit series isn't clear, so we rely on PRs and the merge queue.
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

        jobs = lib.mapAttrs' (
          project: projectConfig:
          let
            cfg = projectConfig.checks;

            # `flutter analyze` is not `dart analyze` with a different name: it
            # resolves the framework packages the project builds against.
            cli = if projectConfig.flutter then "flutter" else "dart";
          in
          lib.nameValuePair "checks${suffix project}" {
            runsOn = "ubuntu-latest";

            steps =
              steps.setup
              ++ lib.optionals cfg.privateDependencies steps.privateDependencies
              ++ [
                {
                  name = "Resolve dependencies";
                  shell = steps.devshell;
                  # `--no-example`, because resolving a package's bundled example
                  # app needs whatever that app needs, and none of the checks
                  # below look at it.
                  run = inProject project "${cli} pub get --no-example";
                }
              ]
              ++ lib.optional cfg.analyze {
                name = "Analyze";
                shell = steps.devshell;
                run = inProject project "${cli} analyze";
              }
              ++ lib.optional projectConfig.linting.dartCodeLinter.enable {
                # The plugin's findings are invisible to `dart analyze`, so
                # without this step the rule set would only ever be enforced in
                # whichever editor happens to load the analysis server.
                #
                # `lib`, because that is where a package's own code lives;
                # pointing it at the repository root would drag generated and
                # vendored code in.
                name = "Lint";
                shell = steps.devshell;
                run = inProject project "dart run dart_code_linter:metrics analyze lib --reporter=github";
              }
              ++ lib.optional (cfg.testCommand != null) {
                name = "Test";
                shell = steps.devshell;
                run = inProject project cfg.testCommand;
              };
          }
        ) projects;
      };
    };
}
