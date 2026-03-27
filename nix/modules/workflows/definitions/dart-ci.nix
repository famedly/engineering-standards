{
  config,
  lib,
  inputs,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib)
    ghExpr
    ghSecret
    nixSetupStep
    mkNixInstallStep
    mkDartPrepareStep
    ciConcurrency
    ;
  nixpkgsRev = inputs.nixpkgs.rev;
  dir = if config.directory != "" then config.directory else null;
  sdkCmd = if config.sdk == "flutter" then "flutter" else "dart";

  setupSteps = [
    { uses = "actions/checkout@${av.checkout}"; }
    (nixSetupStep av.installNix)
    (mkNixInstallStep nixpkgsRev config.sdk)
    {
      uses = "actions/cache@${av.cache}";
      with_ = {
        path = "~/.pub-cache";
        key = "${ghExpr "runner.os"}-pub-${ghExpr "hashFiles('**/pubspec.lock')"}";
      };
    }
    (mkDartPrepareStep { sshKey = ghSecret "ssh_key"; })
    {
      name = "Install dependencies";
      workingDirectory = dir;
      run = "${sdkCmd} pub get";
    }
  ];
in
{
  options = {
    directory = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Subdirectory for the dart project.";
    };
    sdk = lib.mkOption {
      type = lib.types.enum [
        "flutter"
        "dart"
      ];
      default = "flutter";
      description = "Which SDK to install: 'flutter' (default) or 'dart'.";
    };

    importSorter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run import_sorter to check import ordering.";
    };
    dependencyValidator = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run dependency_validator to check for unused dependencies.";
    };
    dartCodeLinter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run dart_code_linter for code metrics and unused code checks.";
    };
    translationsCleaner = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run translations_cleaner to check for unused translations.";
    };
    commentedCodeCheck = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Check for commented-out Dart code.";
    };

    test = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable test job (dart test / flutter test).";
    };
    coverage = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable coverage job with Codecov upload.";
    };
    coverageFlags = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Flags to pass to Codecov (e.g. 'sdk-tests').";
    };
  };

  config.definition = {
    name = "Dart CI";
    on = {
      push.branches = [ "main" ];
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
    permissions.contents = "read";
    concurrency = ciConcurrency;
    jobs = {
      dart_ci = {
        runsOn = "ubuntu-latest";
        steps =
          setupSteps
          ++ [
            {
              name = "Check pubspec.lock is up to date";
              run = "git check-ignore -q pubspec.lock || git diff --exit-code pubspec.lock";
            }
          ]
          ++ lib.optionals config.importSorter [
            {
              name = "Sort imports";
              workingDirectory = dir;
              run = ''
                if ! dart run import_sorter:main --no-comments --exit-if-changed; then
                  dart run import_sorter:main --no-comments
                  {
                    echo '```diff'
                    git diff
                    echo '```'
                  } >> "$GITHUB_STEP_SUMMARY"
                  exit 1
                fi
              '';
            }
          ]
          ++ lib.optionals config.commentedCodeCheck [
            {
              name = "Check for commented-out code";
              run = ''
                if grep -R --include="*.dart" -nE '^[[:space:]]*//[^/<].*;[[:space:]]*$' lib/; then
                  echo "❌ Found commented-out Dart code ending with semicolon."
                  exit 1
                fi
              '';
            }
          ]
          ++ lib.optionals config.dependencyValidator [
            {
              name = "Check unused dependencies";
              run = ''
                dart pub global activate dependency_validator
                dart pub global run dependency_validator
              '';
            }
          ]
          ++ lib.optionals config.dartCodeLinter [
            {
              id = "check_linter";
              name = "dart_code_linter — analyze";
              continueOnError = true;
              workingDirectory = dir;
              run = ''
                if grep -q 'dart_code_linter:' pubspec.yaml; then
                  dart run dart_code_linter:metrics analyze lib --reporter=github
                else
                  echo "::notice::dart_code_linter not in pubspec.yaml — skipping"
                fi
              '';
            }
            {
              name = "dart_code_linter — unused files";
              if_ = "steps.check_linter.outcome == 'success'";
              run = "dart run dart_code_linter:metrics check-unused-files lib";
            }
            {
              name = "dart_code_linter — unused code";
              if_ = "steps.check_linter.outcome == 'success'";
              run = ''dart run dart_code_linter:metrics check-unused-code lib --exclude="{**/generated/**.dart,**.g.dart,**.freezed.dart}"'';
            }
          ]
          ++ lib.optionals config.translationsCleaner [
            {
              name = "Check unused translations";
              workingDirectory = dir;
              continueOnError = true;
              run = ''
                if grep -q 'translations_cleaner:' pubspec.yaml; then
                  rm -f lib/l10n/l10n*.dart
                  ${sdkCmd} pub run translations_cleaner list-unused-terms -a
                fi
              '';
            }
          ];
      };
    }
    // lib.optionalAttrs config.test {
      test = {
        name = "Test";
        runsOn = "ubuntu-latest";
        steps = setupSteps ++ [
          {
            name = "Run tests";
            workingDirectory = dir;
            run = "${sdkCmd} test";
          }
        ];
      };
    }
    // lib.optionalAttrs config.coverage {
      coverage = {
        name = "Coverage";
        runsOn = "ubuntu-latest";
        steps = setupSteps ++ [
          {
            name = "Run tests with coverage";
            workingDirectory = dir;
            run =
              if config.sdk == "flutter" then
                "flutter test --coverage"
              else
                ''
                  dart pub global activate coverage
                  dart pub global run coverage:test_with_coverage
                '';
          }
          {
            uses = "codecov/codecov-action@${av.codecov}";
            with_ = {
              files =
                if config.directory != "" then "${config.directory}/coverage/lcov.info" else "coverage/lcov.info";
              token = ghSecret "CODECOV_TOKEN";
            }
            // lib.optionalAttrs (config.coverageFlags != "") {
              flags = config.coverageFlags;
            };
          }
        ];
      };
    };
  };
}
