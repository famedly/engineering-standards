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
    jobs.dart_ci = {
      runsOn = "ubuntu-latest";
      steps = [
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
      ]
      ++ [
        {
          name = "Install dependencies";
          workingDirectory = if config.directory != "" then config.directory else null;
          run = if config.sdk == "flutter" then "flutter pub get" else "dart pub get";
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
              ${
                if config.sdk == "flutter" then "flutter" else "dart"
              } pub run translations_cleaner list-unused-terms -a
            fi
          '';
        }
      ];
    };
  };
}
