{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
  inherit (import ../../lib/project-paths.nix { inherit lib; }) directory inProject suffix;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
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

              browser = lib.mkOption {
                description = ''
                  Whether this project's tests run in a browser, and therefore
                  need one on `PATH`.

                  See `famedly.standards.dart.projects.<name>.checks.testCommand`
                  for how they are started — this only makes the browser Flutter
                  launches a pinned one.
                '';
                type = lib.types.bool;
                default = false;
              };

              coverage = {
                enable = lib.mkEnableOption "uploading this project's test coverage to Codecov";

                file = lib.mkOption {
                  description = ''
                    Coverage report the test command leaves behind, relative to
                    the project.

                    Producing it is up to `testCommand`, which for Flutter means
                    passing `--coverage`. CI insists on finding it rather than
                    skipping the upload when it is absent: a report that quietly
                    stops being written is how coverage stops being measured
                    without anybody noticing.
                  '';
                  type = lib.types.str;
                  default = "coverage/lcov.info";
                };

                flags = lib.mkOption {
                  description = ''
                    Codecov flag to file this report under, or `null` for none.
                  '';
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "unit-tests";
                };
              };

              licenses = {
                enable = lib.mkEnableOption "checking this project's dependency licences";

                config = lib.mkOption {
                  description = ''
                    Licence policy to check the dependencies against, relative to
                    the project.
                  '';
                  type = lib.types.str;
                  default = "licenses.yaml";
                };

                version = lib.mkOption {
                  description = ''
                    Constraint the `license_checker` tool is installed under.

                    Installed globally rather than carried as a dev dependency,
                    because it resolves the whole of `pana` and would then get a
                    say in which analyzer the project may use — its auditor
                    vetoing the linters it is supposed to audit alongside.
                  '';
                  type = lib.types.str;
                  default = "^1.6.2";
                };
              };

              unused = {
                files = lib.mkOption {
                  description = ''
                    Whether to look for files in `lib` that nothing imports.
                  '';
                  type = lib.types.bool;
                  default = config.linting.dartCodeLinter.enable;
                  defaultText = lib.literalExpression "config.linting.dartCodeLinter.enable";
                };

                code = lib.mkOption {
                  description = ''
                    Whether to look for declarations in `lib` that nothing
                    references.
                  '';
                  type = lib.types.bool;
                  default = config.linting.dartCodeLinter.enable;
                  defaultText = lib.literalExpression "config.linting.dartCodeLinter.enable";
                };

                exclude = lib.mkOption {
                  description = ''
                    Globs the two checks above should not report on.

                    Generated code is excluded by default, and so is whatever
                    `linting.exclude` names: a generator writes what its template
                    says whether anything imports it or not, so a finding there is
                    not something anybody can act on.
                  '';
                  type = lib.types.listOf lib.types.str;

                  default = [
                    "**/generated/**.dart"
                    "**.g.dart"
                    "**.freezed.dart"
                  ]
                  ++ config.linting.exclude;

                  defaultText = lib.literalExpression ''
                    [ "**/generated/**.dart" "**.g.dart" "**.freezed.dart" ] ++ config.linting.exclude
                  '';
                };
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
        )
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

            # One brace-delimited set of globs, quoted so that the shell leaves
            # the braces to the linter instead of expanding them itself.
            unusedExclude = lib.optionalString (cfg.unused.exclude != [ ]) (
              " --exclude='{${lib.concatStringsSep "," cfg.unused.exclude}}'"
            );
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

                {
                  # Resolution just ran, so a lockfile that moved means the one
                  # in the repository was not what the manifest asks for — and
                  # every run before this one resolved something nobody chose.
                  name = "Check that the lockfile is up to date";

                  run = inProject project ''
                    # A library leaves its lockfile untracked on purpose: it
                    # resolves against whatever the application above it picks.
                    if git check-ignore -q pubspec.lock; then
                      exit 0
                    fi

                    # An application that never committed its lockfile leaves
                    # nothing for the comparison below to differ from, and
                    # resolution just wrote one either way.
                    if ! git ls-files --error-unmatch pubspec.lock >/dev/null 2>&1; then
                      echo '::error::pubspec.lock is not committed — run `${cli} pub get` and commit it.'
                      exit 1
                    fi

                    if ! git diff --quiet -- pubspec.lock; then
                      git diff -- pubspec.lock

                      echo '::error::pubspec.lock is out of date — run `${cli} pub get` and commit it.'
                      exit 1
                    fi
                  '';
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
              ++ lib.optional cfg.unused.files {
                # A file nothing imports is either dead or was meant to be
                # wired up and never was. Both are worth knowing, and neither
                # shows up in `dart analyze`.
                name = "Check for unused files";
                shell = steps.devshell;

                run = inProject project "dart run dart_code_linter:metrics check-unused-files lib${unusedExclude}";
              }
              ++ lib.optional cfg.unused.code {
                name = "Check for unused code";
                shell = steps.devshell;

                run = inProject project "dart run dart_code_linter:metrics check-unused-code lib${unusedExclude}";
              }
              ++ lib.optional cfg.dependencies.enable {
                name = "Check the declared dependencies";
                shell = steps.devshell;

                run = inProject project ''
                  dart pub global activate dependency_validator '${cfg.dependencies.version}'

                  dart pub global run dependency_validator
                '';
              }
              ++ lib.optional cfg.licenses.enable {
                # `--problematic`, so a dependency under a licence the policy
                # neither allows nor rejects is raised rather than waved
                # through: an unreviewed licence is not the same as a fine one.
                name = "Check the dependency licences";
                shell = steps.devshell;

                run = inProject project ''
                  dart pub global activate license_checker '${cfg.licenses.version}'

                  dart pub global run license_checker \
                  	-c ${cfg.licenses.config} check-licenses --problematic
                '';
              }
              ++ lib.optional (cfg.testCommand != null) {
                name = "Test";
                shell = steps.devshell;
                run = inProject project cfg.testCommand;
              }
              ++ lib.optionals cfg.coverage.enable [
                {
                  # Codecov's own error for a missing file says little about
                  # why it is missing, and this is the failure that hid for a
                  # long time behind a condition that skipped the upload.
                  name = "Check that the tests produced a coverage report";
                  run = inProject project ''
                    if ! test -s ${cfg.coverage.file}; then
                      echo '::error::${cfg.coverage.file} is missing or empty — does the test command ask for coverage?'
                      exit 1
                    fi
                  '';
                }

                {
                  name = "Upload the coverage to Codecov";
                  uses = allowed-actions."codecov/codecov-action".uses;

                  with_ = {
                    files = "${directory project}${cfg.coverage.file}";
                    fail_ci_if_error = true;
                    token = "\${{ secrets.CODECOV_TOKEN }}";
                  }
                  // lib.optionalAttrs (cfg.coverage.flags != null) { inherit (cfg.coverage) flags; };
                }
              ];
          }
        ) projects;
      };
    };
}
