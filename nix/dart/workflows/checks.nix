## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  flake-parts-lib,
  standardsLib,
  ...
}:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
  inherit (standardsLib) directory inProject suffix;
in
{
  imports = [
    (import ../project-options.nix { inherit lib flake-parts-lib; } (
      { config, ... }: {
        options.checks = {
          analyze = lib.mkOption {
            description = "Whether to run `dart analyze` in CI.";
            type = lib.types.bool;
            default = true;
          };

          testCommand = lib.mkOption {
            description = ''
              The command that runs this project's tests in CI, or `null` to run
              none.

              Not defaulted to `dart test`: a suite that needs external services
              has to be wired up by the project itself.
            '';
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "dart test test/unit/";
          };

          browser = lib.mkOption {
            description = ''
              Whether this project's tests run in a browser, and therefore need
              one on `PATH`. Only makes the browser Flutter launches a pinned
              one; starting them is `testCommand`'s business.
            '';
            type = lib.types.bool;
            default = false;
          };

          coverage = {
            enable = lib.mkEnableOption "uploading this project's test coverage to Codecov";

            file = lib.mkOption {
              description = ''
                Coverage report the test command leaves behind, relative to the
                project.

                Producing it is up to `testCommand`, which for Flutter means
                `--coverage`. CI insists on finding it rather than skipping the
                upload: a report that quietly stops being written is how
                coverage stops being measured.
              '';
              type = lib.types.str;
              default = "coverage/lcov.info";
            };

            flags = lib.mkOption {
              description = "Codecov flag to file this report under.";
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "unit-tests";
            };
          };

          licenses = {
            enable = lib.mkEnableOption "checking this project's dependency licences";

            config = lib.mkOption {
              description = ''
                Licence policy to check against, relative to the project.
              '';
              type = lib.types.str;
              default = "licenses.yaml";
            };

            version = lib.mkOption {
              description = ''
                Version of the `license_checker` tool CI installs.

                Installed globally rather than as a dev dependency: it resolves
                the whole of `pana` and would otherwise get a say in which
                analyzer the project may use.
              '';
              type = lib.types.str;
              default = "1.6.2";
            };
          };

          unused = {
            files = lib.mkOption {
              description = "Whether to look for unimported files in `lib`.";
              type = lib.types.bool;
              default = config.linting.dartCodeLinter.enable;
              defaultText = lib.literalExpression "config.linting.dartCodeLinter.enable";
            };

            code = lib.mkOption {
              description = ''
                Whether to look for unreferenced declarations in `lib`.
              '';
              type = lib.types.bool;
              default = config.linting.dartCodeLinter.enable;
              defaultText = lib.literalExpression "config.linting.dartCodeLinter.enable";
            };

            exclude = lib.mkOption {
              description = ''
                Globs the two checks above should not report on.

                Generated code and whatever `linting.exclude` names: a generator
                writes what its template says whether anything imports it or
                not, so a finding there is not actionable.
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

          translations = {
            enable = lib.mkEnableOption ''
              checking this project's ARB files for unused keys and for being
              sorted

              Needs an `l10n.yaml`, which is where the tool finds them
            '';

            version = lib.mkOption {
              description = "Version of the `sweeper` tool CI installs.";
              type = lib.types.str;
              default = "0.4.2";
            };
          };

          privateDependencies = lib.mkOption {
            description = ''
              Whether this project depends on private famedly repositories and
              therefore needs an SSH key to resolve its dependencies. See
              `famedly.standards.ci.steps.privateDependencies`.
            '';
            type = lib.types.bool;
            default = false;
          };
        };
      }
    ))
  ];

  perSystem =
    { config, ... }:
    let
      projects = config.famedly.standards.dart.projects;
    in
    lib.mkIf (projects != { }) {
      githubActions.workflows.dart-checks = {
        name = "Dart checks";

        # The floor for every job here, including one added later.
        permissions.contents = "read";

        # Not on `push`: there the bounds of the commit series are unclear.
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

            # `flutter analyze` resolves the framework packages the project
            # builds against; `dart analyze` does not.
            cli = if projectConfig.flutter then "flutter" else "dart";

            # Quoted, so the shell leaves the braces to the linter.
            unusedExclude = lib.optionalString (cfg.unused.exclude != [ ]) (
              " --exclude='{${lib.concatStringsSep "," cfg.unused.exclude}}'"
            );

            # No lockfile holds these tools, so the version is stated exactly:
            # otherwise a release changes what CI checks between two runs of
            # the same commit.
            activate = tool: version: "dart pub global activate ${tool} '${version}'";
          in
          lib.nameValuePair "checks${suffix project}" {
            runsOn = "ubuntu-latest";

            timeoutMinutes = 30;

            steps =
              steps.setup
              ++ lib.optionals cfg.privateDependencies steps.privateDependencies
              ++ [
                {
                  name = "Resolve dependencies";
                  shell = steps.devshell;
                  # `--no-example`: a bundled example app needs whatever it
                  # needs, and nothing here looks at it.
                  run = inProject project "${cli} pub get --no-example";
                }

                {
                  # Resolution just ran, so a lockfile that moved means the
                  # committed one was not what the manifest asks for.
                  name = "Check that the lockfile is up to date";

                  run = inProject project ''
                    # A library leaves its lockfile untracked on purpose: it
                    # resolves against whatever the application above it picks.
                    if git check-ignore -q pubspec.lock; then
                      exit 0
                    fi

                    # Nothing to compare against, and resolution just wrote one.
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
                # `dart analyze` does not see the plugin's findings, so without
                # this step the rules only ever apply in an editor. `lib`,
                # because the repository root drags in vendored code.
                name = "Lint";
                shell = steps.devshell;
                run = inProject project "dart run dart_code_linter:metrics analyze lib --reporter=github";
              }
              ++ lib.optional cfg.unused.files {
                # Dead, or meant to be wired up and never was. `dart analyze`
                # reports neither.
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
                  ${activate "dependency_validator" cfg.dependencies.version}

                  dart pub global run dependency_validator
                '';
              }
              ++ lib.optional cfg.translations.enable {
                name = "Check the translations";
                shell = steps.devshell;

                # Sorting keeps two branches from appending a key at the same
                # place and conflicting. There is no check-only mode, so the
                # sort runs and the question is whether it changed anything.
                run = inProject project ''
                  ${activate "sweeper" cfg.translations.version}

                  dart pub global run sweeper check

                  dart pub global run sweeper sort

                  if ! git diff --quiet -- '*.arb'; then
                    git diff -- '*.arb'

                    echo '::error::ARB files are not sorted — run `dart pub global run sweeper sort` and commit the result.'
                    exit 1
                  fi
                '';
              }
              ++ lib.optional cfg.licenses.enable {
                # `--problematic`: a licence the policy neither allows nor
                # rejects is unreviewed, not fine.
                name = "Check the dependency licences";
                shell = steps.devshell;

                run = inProject project ''
                  ${activate "license_checker" cfg.licenses.version}

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
                  # Codecov's own error says little about why the file is
                  # missing.
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
