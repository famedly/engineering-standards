{
  config,
  lib,
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
    mkNixGitAuthStep
    mkDartPrepareStep
    ciConcurrency
    ;

  packageOptions = {
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

    dependencyValidator = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run dependency_validator to check for unused dependencies.";
    };
    translationsCleaner = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run translations_cleaner to check for unused translations.";
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
    testInDevShell = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run test/coverage commands inside `nix develop`. Enable this when
        tests depend on native libraries (e.g. sqlite3 for sqflite_common_ffi)
        that the Nix-installed SDK cannot find on its own.
      '';
    };
  };

  multiPackage = config.packages != { };

  effectivePackages =
    if multiPackage then
      config.packages
    else
      {
        default = {
          inherit (config)
            directory
            sdk
            dependencyValidator
            translationsCleaner
            test
            coverage
            coverageFlags
            testInDevShell
            ;
        };
      };

  jobName = base: pkgName: if multiPackage then "${base}_${pkgName}" else base;

  jobDisplayName = base: pkgName: if multiPackage then "${base} — ${pkgName}" else base;

  # Install SDK from the consumer flake's pinned package (same as DevShell).
  # Dart is installed directly via nix profile (read-only store is fine).
  # Flutter needs a writable copy because it writes to bin/cache/ at runtime.
  mkSdkInstallStep =
    sdk:
    if sdk == "flutter" then
      {
        name = "Install flutter SDK (pinned)";
        run = ''
          nix build .#famedly-flutter-sdk --no-link --print-out-paths > /tmp/flutter-store-path
          cp -rL "$(cat /tmp/flutter-store-path)" "$HOME/flutter-sdk"
          chmod -R u+w "$HOME/flutter-sdk"
          echo "$HOME/flutter-sdk/flutter/bin" >> "$GITHUB_PATH"
        '';
      }
    else
      {
        name = "Install dart SDK (pinned)";
        run = "nix profile install .#famedly-dart-sdk";
      };

  mkSetupSteps =
    pkg:
    let
      dir = if pkg.directory != "" then pkg.directory else null;
      sdkCmd = if pkg.sdk == "flutter" then "flutter" else "dart";
    in
    [
      { uses = "actions/checkout@${av.checkout}"; }
      (nixSetupStep av.installNix)
      (mkNixGitAuthStep { token = ghSecret "ENGINEERING_STANDARDS_READ"; })
      (mkSdkInstallStep pkg.sdk)
    ]
    ++ [
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

  mkLintJob =
    pkgName: pkg:
    let
      dir = if pkg.directory != "" then pkg.directory else null;
      sdkCmd = if pkg.sdk == "flutter" then "flutter" else "dart";
      setupSteps = mkSetupSteps pkg;
    in
    {
      ${jobName "dart_ci" pkgName} = {
        name = jobDisplayName "Dart CI" pkgName;
        runsOn = "ubuntu-latest";
        steps =
          setupSteps
          ++ [
            {
              name = "Check pubspec.lock is up to date";
              run = "git check-ignore -q pubspec.lock || git diff --exit-code pubspec.lock";
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
          ++ lib.optionals pkg.translationsCleaner [
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
    };

  mkTestJob =
    pkgName: pkg:
    let
      dir = if pkg.directory != "" then pkg.directory else null;
      sdkCmd = if pkg.sdk == "flutter" then "flutter" else "dart";
      setupSteps = mkSetupSteps pkg;
      wrap = cmd: if pkg.testInDevShell then "nix develop --command bash -c '${cmd}'" else cmd;
    in
    lib.optionalAttrs pkg.test {
      ${jobName "test" pkgName} = {
        name = jobDisplayName "Test" pkgName;
        runsOn = "ubuntu-latest";
        steps = setupSteps ++ [
          {
            name = "Run tests";
            workingDirectory = dir;
            run = wrap "${sdkCmd} test";
          }
        ];
      };
    };

  mkCoverageJob =
    pkgName: pkg:
    let
      dir = if pkg.directory != "" then pkg.directory else null;
      setupSteps = mkSetupSteps pkg;
      wrap = cmd: if pkg.testInDevShell then "nix develop --command bash -c '${cmd}'" else cmd;
    in
    lib.optionalAttrs pkg.coverage {
      ${jobName "coverage" pkgName} = {
        name = jobDisplayName "Coverage" pkgName;
        runsOn = "ubuntu-latest";
        steps = setupSteps ++ [
          {
            name = "Run tests with coverage";
            workingDirectory = dir;
            run =
              if pkg.sdk == "flutter" then
                wrap "flutter test --coverage"
              else
                wrap ''
                  dart pub global activate coverage
                  dart pub global run coverage:test_with_coverage
                '';
          }
          {
            uses = "codecov/codecov-action@${av.codecov}";
            with_ = {
              files = if pkg.directory != "" then "${pkg.directory}/coverage/lcov.info" else "coverage/lcov.info";
              token = ghSecret "CODECOV_TOKEN";
            }
            // lib.optionalAttrs (pkg.coverageFlags != "") { flags = pkg.coverageFlags; };
          }
        ];
      };
    };

  mkPackageJobs =
    pkgName: pkg: mkLintJob pkgName pkg // mkTestJob pkgName pkg // mkCoverageJob pkgName pkg;

  allJobs = lib.pipe effectivePackages [
    (lib.mapAttrsToList mkPackageJobs)
    (builtins.foldl' (a: b: a // b) { })
  ];
in
{
  options = packageOptions // {
    packages = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule { options = packageOptions; });
      default = { };
      description = ''
        Per-package configurations for multi-package repos.
        When non-empty, generates independent jobs per package and
        ignores the top-level package options.
      '';
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
    jobs = allJobs;
  };
}
