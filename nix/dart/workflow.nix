# Dart CI workflow.
#
# Generated as `.github/workflows/dart-ci.yml` (via github-actions-nix +
# filegen) whenever `famedly.standards.dart.projects` is non-empty. Each
# configured project gets its own lint job, plus optional test and coverage
# jobs.
#
# Dart/Flutter checks cannot run inside the Nix sandbox (they need `pub get`,
# which requires network access), so the real quality checks live here in CI
# rather than in `prek`. The pinned SDK packages from `./sdk.nix` are reused
# so CI and the DevShell share identical toolchain binaries.
{ config, lib, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;

  ghExpr = expression: "\${{ ${expression} }}";
  ghSecret = name: ghExpr "secrets.${name}";

  ciConcurrency = {
    group = "${ghExpr "github.workflow"}-${ghExpr "github.ref"}";
    cancelInProgress = true;
  };

  sdkCmd = pkg: if pkg.sdk == "flutter" then "flutter" else "dart";

  # Configure git HTTPS credentials so the Nix daemon can fetch private flake
  # inputs (e.g. the engineering-standards flake itself). A no-op when the
  # token secret is unset, so public consumers need no extra setup.
  nixGitAuthStep = {
    name = "Configure Git auth for Nix daemon";
    shell = "bash";
    env.GH_TOKEN = ghSecret "ENGINEERING_STANDARDS_READ";
    run = ''
      set -euo pipefail
      if [[ -n "''${GH_TOKEN:-}" ]]; then
        sudo git config --system url."https://x-access-token:''${GH_TOKEN}@github.com/".insteadOf "https://github.com/"
      fi
    '';
  };

  # Configure SSH so private pub dependencies can be fetched. A no-op when the
  # `ssh_key` secret is unset.
  dartPrepareStep = {
    name = "Configure SSH for private dependencies";
    shell = "bash";
    env.SSH_KEY = ghSecret "ssh_key";
    run = ''
      set -euo pipefail
      if [[ -n "''${SSH_KEY:-}" ]]; then
        mkdir -p ~/.ssh
        echo "''${SSH_KEY}" > ~/.ssh/id_rsa
        chmod 600 ~/.ssh/id_rsa
        eval "$(ssh-agent)"
        ssh-add ~/.ssh/id_rsa
        ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
        git config --global url."git@github.com:".insteadOf "https://github.com/"
      fi
      if command -v flutter &>/dev/null; then flutter --disable-analytics; fi
      if command -v dart &>/dev/null; then dart --disable-analytics; fi
    '';
  };

  # Install the pinned SDK exposed by this flake. Dart runs straight from the
  # read-only store; Flutter needs a writable copy because it writes to
  # bin/cache/ at runtime.
  mkSdkInstallStep =
    sdk:
    if sdk == "flutter" then
      {
        name = "Install Flutter SDK (pinned)";
        run = ''
          flutter_path="$(nix build .#famedly-flutter-sdk --no-link --print-out-paths)"
          cp -rL "$flutter_path" "$HOME/flutter-sdk"
          chmod -R u+w "$HOME/flutter-sdk"
          echo "$HOME/flutter-sdk/flutter/bin" >> "$GITHUB_PATH"
        '';
      }
    else
      {
        name = "Install Dart SDK (pinned)";
        run = "nix profile install .#famedly-dart-sdk";
      };

  mkSetupSteps = dir: pkg: [
    { uses = allowed-actions."actions/checkout".uses; }
    { uses = allowed-actions."cachix/install-nix-action".uses; }
    nixGitAuthStep
    (mkSdkInstallStep pkg.sdk)
    {
      uses = allowed-actions."actions/cache".uses;
      with_ = {
        path = "~/.pub-cache";
        key = "${ghExpr "runner.os"}-pub-${ghExpr "hashFiles('**/pubspec.lock')"}";
      };
    }
    dartPrepareStep
    {
      name = "Install dependencies";
      workingDirectory = dir;
      run = "${sdkCmd pkg} pub get";
    }
  ];

  mkLintJob = dir: pkg: {
    runsOn = "ubuntu-latest";
    steps =
      mkSetupSteps dir pkg
      ++ [
        {
          name = "Check pubspec.lock is up to date";
          run = "git check-ignore -q pubspec.lock || git diff --exit-code pubspec.lock";
        }
      ]
      ++ lib.optionals pkg.importSorter [
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
      ++ lib.optionals pkg.commentedCodeCheck [
        {
          name = "Check for commented-out code";
          workingDirectory = dir;
          run = ''
            if grep -R --include="*.dart" -nE '^[[:space:]]*//[^/<].*;[[:space:]]*$' lib/; then
              echo "Found commented-out Dart code ending with a semicolon."
              exit 1
            fi
          '';
        }
      ]
      ++ lib.optionals pkg.dependencyValidator [
        {
          name = "Check unused dependencies";
          workingDirectory = dir;
          run = ''
            dart pub global activate dependency_validator
            dart pub global run dependency_validator
          '';
        }
      ]
      ++ lib.optionals pkg.dartCodeLinter [
        {
          name = "dart_code_linter — analyze";
          continueOnError = true;
          workingDirectory = dir;
          run = ''
            if ! grep -q 'dart_code_linter:' pubspec.yaml; then
              echo "::notice::dart_code_linter not in pubspec.yaml — skipping"
              exit 0
            fi
            dirs=""
            [ -d lib ] && dirs="$dirs lib"
            [ -d bin ] && dirs="$dirs bin"
            if [ -z "$dirs" ]; then
              echo "::notice::No lib/ or bin/ directory — skipping"
              exit 0
            fi
            dart run dart_code_linter:metrics analyze $dirs --reporter=github --set-exit-on-violation-level=noted
          '';
        }
        {
          name = "dart_code_linter — unused files";
          workingDirectory = dir;
          run = ''
            if ! grep -q 'dart_code_linter:' pubspec.yaml; then
              echo "::notice::dart_code_linter not in pubspec.yaml — skipping"
              exit 0
            fi
            dirs=""
            [ -d lib ] && dirs="$dirs lib"
            [ -d bin ] && dirs="$dirs bin"
            if [ -z "$dirs" ]; then
              echo "::notice::No lib/ or bin/ directory — skipping"
              exit 0
            fi
            dart run dart_code_linter:metrics check-unused-files $dirs
          '';
        }
        {
          name = "dart_code_linter — unused code";
          workingDirectory = dir;
          run = ''
            if ! grep -q 'dart_code_linter:' pubspec.yaml; then
              echo "::notice::dart_code_linter not in pubspec.yaml — skipping"
              exit 0
            fi
            dirs=""
            [ -d lib ] && dirs="$dirs lib"
            [ -d bin ] && dirs="$dirs bin"
            if [ -z "$dirs" ]; then
              echo "::notice::No lib/ or bin/ directory — skipping"
              exit 0
            fi
            dart run dart_code_linter:metrics check-unused-code $dirs --exclude="{**/generated/**.dart,**.g.dart,**.freezed.dart}"
          '';
        }
      ]
      ++ lib.optionals pkg.translationsCleaner [
        {
          name = "Check unused translations";
          workingDirectory = dir;
          continueOnError = true;
          run = ''
            if grep -q 'translations_cleaner:' pubspec.yaml; then
              rm -f lib/l10n/l10n*.dart
              ${sdkCmd pkg} pub run translations_cleaner list-unused-terms -a
            fi
          '';
        }
      ];
  };

  mkTestJob =
    dir: pkg:
    let
      wrap = cmd: if pkg.testInDevShell then "nix develop --command bash -c '${cmd}'" else cmd;
    in
    {
      runsOn = "ubuntu-latest";
      steps = mkSetupSteps dir pkg ++ [
        {
          name = "Run tests";
          workingDirectory = dir;
          run = wrap "${sdkCmd pkg} test";
        }
      ];
    };

  mkCoverageJob =
    dir: pkg:
    let
      wrap = cmd: if pkg.testInDevShell then "nix develop --command bash -c '${cmd}'" else cmd;
    in
    {
      runsOn = "ubuntu-latest";
      steps = mkSetupSteps dir pkg ++ [
        {
          name = "Run tests with coverage";
          workingDirectory = dir;
          run =
            if pkg.sdk == "flutter" then
              wrap "flutter test --coverage"
            else
              wrap "dart pub global activate coverage && dart pub global run coverage:test_with_coverage";
        }
        {
          uses = allowed-actions."codecov/codecov-action".uses;
          with_ = {
            files = if dir == null then "coverage/lcov.info" else "${dir}/coverage/lcov.info";
            token = ghSecret "CODECOV_TOKEN";
          }
          // lib.optionalAttrs (pkg.coverageFlags != "") {
            flags = pkg.coverageFlags;
          };
        }
      ];
    };

  # The attribute key is the project's relative path. Use `.` for a
  # single-project repository; subdirectory keys become job-name suffixes so
  # multi-package repositories get independent, uniquely named jobs.
  isRoot = name: name == ".";
  slug =
    name: lib.replaceStrings [ "/" "." "-" " " ] [ "_" "_" "_" "_" ] (lib.removePrefix "./" name);
  jobName = base: name: if isRoot name then base else "${base}_${slug name}";
  jobLabel = base: name: if isRoot name then base else "${base} (${name})";

  mkPackageJobs =
    name: pkg:
    let
      dir = if isRoot name then null else name;
    in
    {
      ${jobName "dart_ci" name} = mkLintJob dir pkg // {
        name = jobLabel "Dart CI" name;
      };
    }
    // lib.optionalAttrs pkg.test {
      ${jobName "test" name} = mkTestJob dir pkg // {
        name = jobLabel "Test" name;
      };
    }
    // lib.optionalAttrs pkg.coverage {
      ${jobName "coverage" name} = mkCoverageJob dir pkg // {
        name = jobLabel "Coverage" name;
      };
    };

  mkJobs =
    projects:
    lib.foldl' (acc: name: acc // mkPackageJobs name projects.${name}) { } (lib.attrNames projects);
in
{
  perSystem =
    psArgs:
    let
      projects = psArgs.config.famedly.standards.dart.projects;
    in
    lib.mkIf (projects != { }) {
      githubActions.workflows.dart-ci = {
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

        jobs = mkJobs projects;
      };
    };
}
