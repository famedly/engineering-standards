{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  repoRoot,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib)
    ghExpr
    ghSecret
    ghEnv
    ciConcurrency
    ;
in
{
  options = {
    envFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Path to .env file for version overrides.";
    };
    directory = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Subdirectory for the dart project.";
    };
  };

  config = {
    definition = {
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
      jobs.dart_ci = lib.mkMerge [
        (lib.mkIf (config.envFile != "") {
          env.env_file = config.envFile;
        })
        {
          runsOn = "ubuntu-latest";
          steps = [
            { uses = "actions/checkout@${av.checkout}"; }
          ]
          ++ lib.optionals (config.envFile != "") [
            {
              name = "Read env file";
              if_ = "env.env_file != ''";
              run = "cat ${ghEnv "env_file"} >> $GITHUB_ENV";
            }
          ]
          ++ [
            {
              uses = "dart-lang/setup-dart@${av.setupDart}";
              if_ = "env.dart_version != ''";
              with_.sdk = ghEnv "dart_version";
            }
            {
              uses = "subosito/flutter-action@${av.flutterAction}";
              with_ = {
                flutter-version = ghEnv "flutter_version";
                cache = true;
              };
            }
            {
              uses = "actions/cache@${av.cache}";
              with_ = {
                path = "~/.pub-cache";
                key = "${ghExpr "runner.os"}-pub-${ghExpr "hashFiles('**/pubspec.lock')"}";
              };
            }
            {
              name = "Set up private deps";
              uses = "./.github/actions/dart-prepare";
              with_ = {
                ssh_key = ghSecret "ssh_key";
                container_mode = "false";
              };
            }
          ]
          ++ [
            {
              name = "Install dependencies";
              workingDirectory = if config.directory != "" then config.directory else null;
              run = "flutter pub get";
            }
            {
              name = "Check pubspec.lock is up to date";
              run = "git check-ignore -q pubspec.lock || git diff --exit-code pubspec.lock";
            }
          ]
          ++ [
            {
              name = "Sort imports";
              workingDirectory = if config.directory != "" then config.directory else null;
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
            {
              name = "Check for commented-out code";
              run = ''
                if grep -R --include="*.dart" -nE '^[[:space:]]*//[^/<].*;[[:space:]]*$' lib/; then
                  echo "❌ Found commented-out Dart code ending with semicolon."
                  exit 1
                fi
              '';
            }
            {
              name = "Check unused dependencies";
              run = ''
                dart pub global activate dependency_validator
                dart pub global run dependency_validator
              '';
            }
            {
              id = "check_linter";
              name = "dart_code_linter — analyze";
              continueOnError = true;
              workingDirectory = if config.directory != "" then config.directory else null;
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
            {
              name = "Check unused translations";
              workingDirectory = if config.directory != "" then config.directory else null;
              continueOnError = true;
              run = ''
                if grep -q 'translations_cleaner:' pubspec.yaml; then
                  rm -f lib/l10n/l10n*.dart
                  flutter pub run translations_cleaner list-unused-terms -a
                fi
              '';
            }
          ];
        }
      ];
    };

    extraManagedFiles = [
      {
        src = "${repoRoot}/.github/actions/dart-prepare/action.yml";
        dest = ".github/actions/dart-prepare/action.yml";
      }
    ];
  };
}
