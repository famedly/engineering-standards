# E2E test suite for engineering-standards modules.
#
# Tests verify that:
#   1. Module evaluation succeeds for realistic consumer configurations
#   2. Expected managed files are generated (presence, content, scoping)
#   3. Negative tests: disabled features produce no files
#   4. Generated workflows pass actionlint
#   5. Template flake.nix files parse without errors
#
# All tests run as part of `nix flake check`.
#
# Usage:
#   nix flake check          — runs all checks including these tests
#   nix build .#checks.x86_64-linux.test-eval-rust-full   — run a single test

{
  inputs,
  pkgs,
  lib,
  system,
}:
let
  dummySelf = {
    outPath = pkgs.emptyDirectory;
    inherit inputs;
  };

  workflowsModule = (import ../modules/workflows) {
    inherit inputs lib;
    flake-parts-lib = inputs.flake-parts.lib;
  };

  preCommitHooksModule = (import ../modules/pre-commit-hooks.nix) {
    inherit inputs lib;
    flake-parts-lib = inputs.flake-parts.lib;
  };

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  evalConsumer =
    name: perSystemConfig:
    inputs.flake-parts.lib.evalFlakeModule
      {
        inherit inputs;
        self = dummySelf;
      }
      {
        imports = [
          ../modules
          workflowsModule
          preCommitHooksModule
        ];
        systems = [ system ];
        perSystem = { ... }: perSystemConfig;
      };

  evalWithBundle =
    name: perSystemConfig:
    let
      eval =
        inputs.flake-parts.lib.evalFlakeModule
          {
            inherit inputs;
            self = dummySelf;
          }
          {
            imports = [
              ../modules
              workflowsModule
              preCommitHooksModule
            ];
            systems = [ system ];
            perSystem =
              {
                config,
                pkgs,
                lib,
                ...
              }:
              lib.mkMerge [
                perSystemConfig
                {
                  packages._testManagedFiles =
                    let
                      files = config.famedly.standards._internal.managedFiles;
                      installCmds = map (
                        entry:
                        let
                          destDir = builtins.dirOf entry.dest;
                        in
                        ''
                          mkdir -p "$out/${destDir}"
                          cp -f ${entry.src} "$out/${entry.dest}"
                          chmod u+w "$out/${entry.dest}"
                        ''
                      ) files;
                    in
                    pkgs.runCommand "managed-files-${name}" { } ''
                      mkdir -p $out
                      ${lib.concatStrings installCmds}
                    '';
                }
              ];
          };
    in
    eval.config.flake.packages.${system}._testManagedFiles;

  # ---------------------------------------------------------------------------
  # Test Scenarios
  # ---------------------------------------------------------------------------

  scenarios = {
    disabled = { };

    minimal = {
      famedly.standards = {
        rules.enable = true;
        preCommitHooks.enable = true;
      };
    };

    rust-full = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [ "rust" ];
        };
        linting = {
          enable = true;
          rust = true;
        };
        preCommitHooks = {
          enable = true;
          rustHooks.enable = true;
        };
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotRust = true;
        };
        devShell.enable = true;
      };
      famedly.github.workflows = {
        ci = {
          enable = true;
          armRunners = true;
        };
        general-checks.enable = true;
        authenticate-commits.enable = true;
        rust-ci.enable = true;
      };
    };

    rust-publish = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [ "rust" ];
        };
        linting = {
          enable = true;
          rust = true;
        };
        preCommitHooks.enable = true;
      };
      famedly.github.workflows = {
        ci.enable = true;
        general-checks.enable = true;
        publish-crate.enable = true;
      };
    };

    rust-backend = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [ "rust" ];
        };
        linting = {
          enable = true;
          rust = true;
        };
        preCommitHooks = {
          enable = true;
          rustHooks.enable = true;
        };
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotRust = true;
        };
      };
      famedly.github.workflows = {
        ci.enable = true;
        general-checks.enable = true;
        authenticate-commits.enable = true;
        rust-ci.enable = true;
        publish-crate.enable = true;
        docker-backend = {
          enable = true;
          targets = "backend-service";
        };
        fast-forward.enable = true;
        add-to-project = {
          enable = true;
          projectUrl = "https://github.com/orgs/famedly/projects/50";
        };
      };
    };

    dart-full = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [ "dart" ];
        };
        linting = {
          enable = true;
          dart = true;
        };
        preCommitHooks = {
          enable = true;
          dartHooks.enable = true;
        };
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotDart = true;
        };
        devShell.enable = true;
        dart = {
          enable = true;
          flutter = false;
        };
      };
      famedly.github.workflows = {
        ci = {
          enable = true;
          armRunners = true;
        };
        general-checks.enable = true;
        dart-ci.enable = true;
      };
    };

    flutter-full = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [
            "dart"
            "flutter"
          ];
        };
        linting = {
          enable = true;
          flutter = true;
        };
        preCommitHooks = {
          enable = true;
          dartHooks.enable = true;
        };
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotDart = true;
        };
        devShell.enable = true;
        dart = {
          enable = true;
          flutter = true;
        };
      };
      famedly.github.workflows = {
        ci.enable = true;
        general-checks.enable = true;
        authenticate-commits.enable = true;
        dart-ci.enable = true;
        publish-pub.enable = true;
        review-app = {
          enable = true;
          projectName = "test-app";
        };
        docker.enable = true;
        github-pages.enable = true;
      };
    };

    docker-backend = {
      famedly.github.workflows = {
        ci.enable = true;
        docker-backend = {
          enable = true;
          targets = "my-service";
        };
      };
    };

    docker-generic = {
      famedly.github.workflows = {
        ci.enable = true;
        docker = {
          enable = true;
          imageName = "my-app";
        };
      };
    };

    ansible = {
      famedly.github.workflows = {
        ci.enable = true;
        ansible-ci = {
          enable = true;
          collection = "famedly.dns";
        };
      };
    };

    monorepo-flutter-rust = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [
            "rust"
            "dart"
            "flutter"
          ];
        };
        preCommitHooks.enable = true;
        infrastructure = {
          editorconfig = true;
          dependabot = true;
        };
        devShell.enable = true;
        projects = {
          backend = {
            language = "rust";
            directory = "backend";
          };
          frontend = {
            language = "flutter";
            directory = "frontend";
          };
        };
      };
      famedly.github.workflows = {
        ci = {
          enable = true;
          armRunners = true;
        };
        general-checks.enable = true;
        dart-ci = {
          enable = true;
          directory = "frontend";
        };
      };
    };

    monorepo-dart-rust-ffi = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [
            "dart"
            "rust"
          ];
        };
        preCommitHooks.enable = true;
        infrastructure = {
          editorconfig = true;
          dependabot = true;
        };
        projects = {
          main = {
            language = "dart";
            directory = "";
          };
          native = {
            language = "rust";
            directory = "rust";
          };
        };
      };
      famedly.github.workflows.ci.enable = true;
    };

    dart-test-coverage = {
      famedly.standards = {
        rules.enable = true;
        dart = {
          enable = true;
          flutter = false;
        };
      };
      famedly.github.workflows = {
        ci.enable = true;
        dart-ci = {
          enable = true;
          sdk = "dart";
          test = true;
          coverage = true;
          coverageFlags = "unit-tests";
        };
      };
    };

    flutter-test-coverage = {
      famedly.standards = {
        dart = {
          enable = true;
          flutter = true;
        };
      };
      famedly.github.workflows = {
        ci.enable = true;
        dart-ci = {
          enable = true;
          test = true;
          coverage = true;
        };
      };
    };

    dart-minimal-lint = {
      famedly.github.workflows = {
        ci.enable = true;
        dart-ci = {
          enable = true;
          sdk = "dart";
          importSorter = false;
          dependencyValidator = false;
          dartCodeLinter = false;
          translationsCleaner = false;
          commentedCodeCheck = false;
        };
      };
    };

    dart-multi-package = {
      famedly.github.workflows = {
        ci.enable = true;
        dart-ci = {
          enable = true;
          packages = {
            sdk = {
              directory = "sdk";
              sdk = "dart";
              test = true;
              coverage = true;
              coverageFlags = "sdk-tests";
            };
            app = {
              directory = "example/app";
              sdk = "flutter";
              test = true;
              coverage = false;
              importSorter = false;
            };
          };
        };
      };
    };

    monorepo-selective = {
      famedly.standards = {
        infrastructure.dependabot = true;
        preCommitHooks.enable = true;
        projects = {
          api = {
            language = "rust";
            directory = "api";
            dependabot = false;
          };
          worker = {
            language = "python";
            directory = "worker";
            hooks = false;
          };
        };
      };
      famedly.github.workflows.ci.enable = true;
    };

    hookd-deploy = {
      famedly.github.workflows = {
        ci.enable = true;
        docker.enable = true;
        hookd-deploy = {
          enable = true;
          hookdUrl = "https://my-service-webhook.famedly.de";
        };
      };
    };

    docker-simple = {
      famedly.github.workflows = {
        ci.enable = true;
        docker = {
          enable = true;
          mode = "simple";
          imageName = "my-simple-app";
          registry = "registry.example.com";
          registryUser = "ci-user";
          registryPasswordSecret = "REGISTRY_PASSWORD";
          pushOnlyOnTags = true;
          buildArgs.VERSION = "\${{ github.ref_name }}";
        };
      };
    };

    docker-workflow-run = {
      famedly.github.workflows = {
        ci.enable = true;
        docker = {
          enable = true;
          mode = "simple";
          triggerMode = "workflowRun";
          triggerWorkflow = "CI";
          imageName = "my-app";
          registryPasswordSecret = "REGISTRY_PASSWORD";
          pushOnlyOnTags = true;
        };
      };
    };

    review-app-workflow-run = {
      famedly.github.workflows = {
        ci.enable = true;
        review-app = {
          enable = true;
          triggerMode = "workflowRun";
          triggerWorkflow = "CI";
          projectName = "test-review";
        };
      };
    };

    github-pages-custom = {
      famedly.github.workflows = {
        ci.enable = true;
        github-pages = {
          enable = true;
          triggerWorkflows = [ "Integration Tests" ];
          artifactName = "test-results";
        };
      };
    };

    kitchen-sink = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [
            "rust"
            "dart"
            "flutter"
          ];
        };
        linting = {
          enable = true;
          rust = true;
          dart = true;
          flutter = true;
          python = true;
          typescript = true;
        };
        preCommitHooks = {
          enable = true;
          rustHooks.enable = true;
          dartHooks.enable = true;
          pythonHooks.enable = true;
        };
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotRust = true;
          dependabotDart = true;
          dependabotPython = true;
          dependabotDocker = true;
          dependabotNpm = true;
          dependabotTerraform = true;
        };
        devShell.enable = true;
      };
      famedly.github.workflows = {
        ci = {
          enable = true;
          armRunners = true;
        };
        general-checks.enable = true;
        authenticate-commits.enable = true;
        fast-forward.enable = true;
        add-to-project = {
          enable = true;
          projectUrl = "https://github.com/orgs/famedly/projects/42";
        };
        update-openpgp-policy = {
          enable = true;
          teams = ''["backend"]'';
        };
        rust-ci.enable = true;
        publish-crate.enable = true;
        dart-ci.enable = true;
        publish-pub.enable = true;
        review-app = {
          enable = true;
          projectName = "test-app";
          environment = "review";
        };
        docker-backend = {
          enable = true;
          targets = "svc-a,svc-b";
        };
        docker = {
          enable = true;
          imageName = "my-app";
          registry = "ghcr.io";
          registryPasswordSecret = "GITHUB_TOKEN";
        };
        github-pages = {
          enable = true;
          artifactName = "docs";
        };
        ansible-ci = {
          enable = true;
          collection = "famedly.test";
        };
        hookd-deploy = {
          enable = true;
          hookdUrl = "https://my-webhook.famedly.de";
        };
      };
    };
  };

  # ---------------------------------------------------------------------------
  # 1. Evaluation Tests
  # ---------------------------------------------------------------------------

  evalTests = lib.mapAttrs' (
    name: config:
    let
      eval = evalConsumer name config;
      forced = builtins.deepSeq {
        apps = builtins.attrNames (eval.config.flake.apps.${system} or { });
        checks = builtins.attrNames (eval.config.flake.checks.${system} or { });
        packages = builtins.attrNames (eval.config.flake.packages.${system} or { });
        devShells = builtins.attrNames (eval.config.flake.devShells.${system} or { });
      } true;
    in
    lib.nameValuePair "test-eval-${name}" (
      assert forced;
      pkgs.runCommand "test-eval-${name}" { } ''
        echo "PASS: module evaluation for scenario '${name}'"
        touch $out
      ''
    )
  ) scenarios;

  # ---------------------------------------------------------------------------
  # 2. Content Tests
  # ---------------------------------------------------------------------------

  rustBundle = evalWithBundle "rust-full" scenarios.rust-full;
  rustPublishBundle = evalWithBundle "rust-publish" scenarios.rust-publish;
  rustBackendBundle = evalWithBundle "rust-backend" scenarios.rust-backend;
  dartBundle = evalWithBundle "dart-full" scenarios.dart-full;
  flutterBundle = evalWithBundle "flutter-full" scenarios.flutter-full;
  kitchenSinkBundle = evalWithBundle "kitchen-sink" scenarios.kitchen-sink;
  monorepoFlutterRustBundle = evalWithBundle "monorepo-flutter-rust" scenarios.monorepo-flutter-rust;
  monorepoDartRustFfiBundle = evalWithBundle "monorepo-dart-rust-ffi" scenarios.monorepo-dart-rust-ffi;
  monorepoSelectiveBundle = evalWithBundle "monorepo-selective" scenarios.monorepo-selective;
  dockerBackendBundle = evalWithBundle "docker-backend" scenarios.docker-backend;
  dockerGenericBundle = evalWithBundle "docker-generic" scenarios.docker-generic;
  ansibleBundle = evalWithBundle "ansible" scenarios.ansible;
  dartTestCoverageBundle = evalWithBundle "dart-test-coverage" scenarios.dart-test-coverage;
  flutterTestCoverageBundle = evalWithBundle "flutter-test-coverage" scenarios.flutter-test-coverage;
  dartMinimalLintBundle = evalWithBundle "dart-minimal-lint" scenarios.dart-minimal-lint;
  dartMultiPackageBundle = evalWithBundle "dart-multi-package" scenarios.dart-multi-package;
  hookdDeployBundle = evalWithBundle "hookd-deploy" scenarios.hookd-deploy;
  dockerSimpleBundle = evalWithBundle "docker-simple" scenarios.docker-simple;
  dockerWorkflowRunBundle = evalWithBundle "docker-workflow-run" scenarios.docker-workflow-run;
  reviewAppWorkflowRunBundle = evalWithBundle "review-app-workflow-run" scenarios.review-app-workflow-run;
  githubPagesCustomBundle = evalWithBundle "github-pages-custom" scenarios.github-pages-custom;
  disabledBundle = evalWithBundle "disabled" scenarios.disabled;

  disabledScriptEval = evalConsumer "script-test-disabled" scenarios.disabled;
  disabledScript = disabledScriptEval.config.flake.apps.${system}.regenerateStandards.program;

  minimalScriptEval = evalConsumer "script-test-minimal" scenarios.minimal;
  minimalScript = minimalScriptEval.config.flake.apps.${system}.regenerateStandards.program;

  dartScriptEval = evalConsumer "script-test-dart" scenarios.dart-full;
  dartScript = dartScriptEval.config.flake.apps.${system}.regenerateStandards.program;

  contentTests = {
    test-content-rust = pkgs.runCommand "test-content-rust" { } ''
      echo "=== Checking Rust consumer managed files ==="

      test -f ${rustBundle}/.github/workflows/ci.yml
      grep -q "arm-ubuntu-latest" ${rustBundle}/.github/workflows/ci.yml

      # Rust CI — complete workflow (no workflow_call reference)
      test -f ${rustBundle}/.github/workflows/rust-ci.yml
      grep -q "Tests" ${rustBundle}/.github/workflows/rust-ci.yml
      ! grep -q "workflow_call" ${rustBundle}/.github/workflows/rust-ci.yml

      test -f ${rustBundle}/.github/workflows/general-checks.yml
      test -f ${rustBundle}/.github/workflows/authenticate-commits.yml

      test -f ${rustBundle}/.editorconfig
      test -f ${rustBundle}/.github/dependabot.yml
      grep -q "cargo" ${rustBundle}/.github/dependabot.yml

      test -f ${rustBundle}/clippy.toml
      test -f ${rustBundle}/rustfmt.toml
      test -f ${rustBundle}/CLAUDE.md
      test -d ${rustBundle}/.cursor/rules/standards

      echo "PASS: all expected Rust managed files present and correct"
      touch $out
    '';

    test-content-rust-backend = pkgs.runCommand "test-content-rust-backend" { } ''
      echo "=== Checking Rust backend consumer managed files ==="

      test -f ${rustBackendBundle}/.github/workflows/ci.yml
      test -f ${rustBackendBundle}/.github/workflows/rust-ci.yml
      test -f ${rustBackendBundle}/.github/workflows/publish-crate.yml
      test -f ${rustBackendBundle}/.github/workflows/docker-backend.yml

      test -f ${rustBackendBundle}/.github/workflows/general-checks.yml
      test -f ${rustBackendBundle}/.github/workflows/authenticate-commits.yml
      test -f ${rustBackendBundle}/.github/workflows/fast-forward.yml
      test -f ${rustBackendBundle}/.github/workflows/add-to-project.yml

      grep -q "issue_comment" ${rustBackendBundle}/.github/workflows/fast-forward.yml
      grep -q "backend-service" ${rustBackendBundle}/.github/workflows/docker-backend.yml

      # No workflow_call references in any workflow
      ! grep -rq "workflow_call" ${rustBackendBundle}/.github/workflows/

      echo "PASS: all expected Rust backend managed files present and correct"
      touch $out
    '';

    test-content-dart = pkgs.runCommand "test-content-dart" { } ''
      echo "=== Checking Dart consumer managed files ==="

      test -f ${dartBundle}/.github/workflows/ci.yml
      test -f ${dartBundle}/.github/workflows/dart-ci.yml
      test -f ${dartBundle}/.github/workflows/general-checks.yml
      test -f ${dartBundle}/.editorconfig
      test -f ${dartBundle}/.github/dependabot.yml
      grep -q "pub" ${dartBundle}/.github/dependabot.yml
      test -f ${dartBundle}/analysis_options.yaml
      test -f ${dartBundle}/analysis_options.standards.yaml
      grep -q "analysis_options.standards.yaml" ${dartBundle}/analysis_options.yaml
      test -f ${dartBundle}/CLAUDE.md

      echo "PASS: all expected Dart managed files present and correct"
      touch $out
    '';

    test-content-flutter = pkgs.runCommand "test-content-flutter" { } ''
      echo "=== Checking Flutter consumer managed files ==="
      test -f ${flutterBundle}/analysis_options.yaml
      test -f ${flutterBundle}/analysis_options.standards.yaml
      grep -q "flutter" ${flutterBundle}/analysis_options.standards.yaml
      ! grep -q "engineering_standards_lints" ${flutterBundle}/analysis_options.standards.yaml
      grep -q "analysis_options.standards.yaml" ${flutterBundle}/analysis_options.yaml

      test -f ${flutterBundle}/.github/workflows/ci.yml
      test -f ${flutterBundle}/.github/workflows/dart-ci.yml
      test -f ${flutterBundle}/.github/workflows/publish-pub.yml
      test -f ${flutterBundle}/.github/workflows/general-checks.yml
      test -f ${flutterBundle}/.github/workflows/authenticate-commits.yml
      test -f ${flutterBundle}/.github/workflows/docker.yml
      test -f ${flutterBundle}/.github/workflows/github-pages.yml
      test -f ${flutterBundle}/.editorconfig
      test -f ${flutterBundle}/CLAUDE.md

      grep -q "pages: write" ${flutterBundle}/.github/workflows/github-pages.yml

      test -f ${flutterBundle}/.github/workflows/review-app.yml

      echo "PASS: all expected Flutter managed files present and correct"
      touch $out
    '';

    test-content-kitchen-sink = pkgs.runCommand "test-content-kitchen-sink" { } ''
      echo "=== Checking kitchen-sink consumer managed files ==="

      test -f ${kitchenSinkBundle}/.github/workflows/ci.yml
      test -f ${kitchenSinkBundle}/.github/workflows/general-checks.yml
      test -f ${kitchenSinkBundle}/.github/workflows/authenticate-commits.yml
      test -f ${kitchenSinkBundle}/.github/workflows/fast-forward.yml
      test -f ${kitchenSinkBundle}/.github/workflows/add-to-project.yml
      test -f ${kitchenSinkBundle}/.github/workflows/update-openpgp-policy.yml
      test -f ${kitchenSinkBundle}/.github/workflows/rust-ci.yml
      test -f ${kitchenSinkBundle}/.github/workflows/publish-crate.yml
      test -f ${kitchenSinkBundle}/.github/workflows/dart-ci.yml
      test -f ${kitchenSinkBundle}/.github/workflows/publish-pub.yml
      test -f ${kitchenSinkBundle}/.github/workflows/review-app.yml
      test -f ${kitchenSinkBundle}/.github/workflows/docker-backend.yml
      test -f ${kitchenSinkBundle}/.github/workflows/docker.yml
      test -f ${kitchenSinkBundle}/.github/workflows/github-pages.yml
      test -f ${kitchenSinkBundle}/.github/workflows/ansible-ci.yml
      test -f ${kitchenSinkBundle}/.github/workflows/hookd-deploy.yml
      test -f ${kitchenSinkBundle}/.github/workflows/hookd.py

      test -f ${kitchenSinkBundle}/.editorconfig
      test -f ${kitchenSinkBundle}/.github/dependabot.yml
      test -f ${kitchenSinkBundle}/CLAUDE.md

      grep -q "cargo"     ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "pub"       ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "pip"       ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "docker"    ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "npm"       ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "terraform" ${kitchenSinkBundle}/.github/dependabot.yml

      grep -q "arm-ubuntu-latest" ${kitchenSinkBundle}/.github/workflows/ci.yml

      # No workflow_call references anywhere
      ! grep -rq "workflow_call" ${kitchenSinkBundle}/.github/workflows/

      echo "PASS: all expected kitchen-sink managed files present and correct"
      touch $out
    '';

    test-content-monorepo-flutter-rust = pkgs.runCommand "test-content-monorepo-flutter-rust" { } ''
      echo "=== Checking Flutter+Rust monorepo managed files ==="

      test -f ${monorepoFlutterRustBundle}/backend/clippy.toml
      test -f ${monorepoFlutterRustBundle}/backend/rustfmt.toml
      test -f ${monorepoFlutterRustBundle}/backend/deny.toml

      test -f ${monorepoFlutterRustBundle}/frontend/analysis_options.yaml
      test -f ${monorepoFlutterRustBundle}/frontend/analysis_options.standards.yaml

      ! test -f ${monorepoFlutterRustBundle}/clippy.toml
      ! test -f ${monorepoFlutterRustBundle}/rustfmt.toml
      ! test -f ${monorepoFlutterRustBundle}/analysis_options.yaml

      test -f ${monorepoFlutterRustBundle}/.github/dependabot.yml
      grep -q "cargo" ${monorepoFlutterRustBundle}/.github/dependabot.yml
      grep -q "pub" ${monorepoFlutterRustBundle}/.github/dependabot.yml
      grep -q "/backend" ${monorepoFlutterRustBundle}/.github/dependabot.yml
      grep -q "/frontend" ${monorepoFlutterRustBundle}/.github/dependabot.yml

      test -f ${monorepoFlutterRustBundle}/.editorconfig
      test -f ${monorepoFlutterRustBundle}/.github/workflows/ci.yml
      test -f ${monorepoFlutterRustBundle}/CLAUDE.md

      echo "PASS: monorepo Flutter+Rust managed files correctly scoped"
      touch $out
    '';

    test-content-monorepo-dart-rust-ffi = pkgs.runCommand "test-content-monorepo-dart-rust-ffi" { } ''
      echo "=== Checking Dart+Rust FFI monorepo managed files ==="

      test -f ${monorepoDartRustFfiBundle}/analysis_options.yaml
      test -f ${monorepoDartRustFfiBundle}/rust/clippy.toml
      test -f ${monorepoDartRustFfiBundle}/rust/rustfmt.toml

      test -f ${monorepoDartRustFfiBundle}/.github/dependabot.yml
      grep -q "pub" ${monorepoDartRustFfiBundle}/.github/dependabot.yml
      grep -q "cargo" ${monorepoDartRustFfiBundle}/.github/dependabot.yml

      echo "PASS: monorepo Dart+Rust FFI managed files correctly scoped"
      touch $out
    '';

    test-ci-default-runners = pkgs.runCommand "test-ci-default-runners" { } ''
      echo "=== Checking CI with default (non-ARM) runners ==="
      grep -q "ubuntu-latest" ${dockerGenericBundle}/.github/workflows/ci.yml
      ! grep -q "arm-ubuntu-latest" ${dockerGenericBundle}/.github/workflows/ci.yml
      echo "PASS: default runners used when armRunners = false"
      touch $out
    '';

    test-negative-disabled = pkgs.runCommand "test-negative-disabled" { } ''
      echo "=== Checking disabled scenario only produces defaults ==="

      test -f ${disabledBundle}/.editorconfig
      test -f ${disabledBundle}/.github/dependabot.yml

      ! test -d ${disabledBundle}/.github/workflows
      ! test -f ${disabledBundle}/CLAUDE.md
      ! test -f ${disabledBundle}/clippy.toml
      ! test -f ${disabledBundle}/analysis_options.yaml

      count=$(find ${disabledBundle} -type f | wc -l)
      if [ "$count" -ne 2 ]; then
        echo "FAIL: expected exactly 2 default files, got $count:"
        find ${disabledBundle} -type f
        exit 1
      fi

      echo "PASS: disabled scenario produces only default infrastructure files"
      touch $out
    '';

    test-manifest-content =
      pkgs.runCommand "test-manifest-content"
        {
          nativeBuildInputs = [ pkgs.git ];
        }
        ''
          set -euo pipefail
          echo "=== Checking regenerateStandards manifest content ==="

          REPO=$(mktemp -d)
          export HOME="$TMPDIR"
          export GIT_CONFIG_NOSYSTEM=1
          git -C "$REPO" init -q
          git -C "$REPO" config user.email "ci@test"
          git -C "$REPO" config user.name "CI"
          git -C "$REPO" commit --allow-empty -m "init" -q

          cd "$REPO"
          ${minimalScript}

          MANIFEST=".engineering-standards-manifest"
          test -f "$MANIFEST" || { echo "FAIL: manifest not written"; exit 1; }

          grep -q "CLAUDE.md" "$MANIFEST" \
            || { echo "FAIL: CLAUDE.md missing from manifest"; exit 1; }
          grep -q ".cursor/rules/standards" "$MANIFEST" \
            || { echo "FAIL: .cursor/rules/standards missing from manifest"; exit 1; }

          failed=0
          while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if ! test -f "$f"; then
              echo "FAIL: manifest lists '$f' but file does not exist"
              failed=1
            fi
          done < "$MANIFEST"
          [ "$failed" -eq 0 ] || exit 1

          echo "PASS: manifest written with correct content"
          touch $out
        '';

    test-manifest-cleanup =
      pkgs.runCommand "test-manifest-cleanup"
        {
          nativeBuildInputs = [ pkgs.git ];
        }
        ''
          set -euo pipefail
          echo "=== Checking regenerateStandards manifest cleanup ==="

          REPO=$(mktemp -d)
          export HOME="$TMPDIR"
          export GIT_CONFIG_NOSYSTEM=1
          git -C "$REPO" init -q
          git -C "$REPO" config user.email "ci@test"
          git -C "$REPO" config user.name "CI"
          git -C "$REPO" commit --allow-empty -m "init" -q

          cd "$REPO"

          mkdir -p .cursor/rules/standards
          echo "stale rule content" > .cursor/rules/standards/stale.md
          echo "stale CLAUDE" > CLAUDE.md
          printf '.cursor/rules/standards/stale.md\nCLAUDE.md\n.editorconfig\n.github/dependabot.yml\n' \
            > .engineering-standards-manifest

          ${disabledScript}

          if test -f .cursor/rules/standards/stale.md; then
            echo "FAIL: stale .cursor/rules/standards/stale.md was not removed"
            exit 1
          fi
          if test -f CLAUDE.md; then
            echo "FAIL: stale CLAUDE.md was not removed"
            exit 1
          fi
          echo "  PASS: stale rule files removed"

          test -f .editorconfig \
            || { echo "FAIL: .editorconfig missing after cleanup"; exit 1; }
          test -f .github/dependabot.yml \
            || { echo "FAIL: .github/dependabot.yml missing after cleanup"; exit 1; }
          echo "  PASS: default infrastructure files still present"

          if grep -q "CLAUDE.md" .engineering-standards-manifest; then
            echo "FAIL: manifest still references removed CLAUDE.md"
            exit 1
          fi
          if grep -q "stale" .engineering-standards-manifest; then
            echo "FAIL: manifest still references stale files"
            exit 1
          fi
          grep -q ".editorconfig" .engineering-standards-manifest \
            || { echo "FAIL: .editorconfig missing from updated manifest"; exit 1; }
          echo "  PASS: manifest updated to reflect current managed files"

          echo "PASS: manifest cleanup works correctly"
          touch $out
        '';

    test-manifest-initial-only =
      pkgs.runCommand "test-manifest-initial-only"
        {
          nativeBuildInputs = [ pkgs.git ];
        }
        ''
          set -euo pipefail
          echo "=== Checking initialOnly file preservation ==="

          REPO=$(mktemp -d)
          export HOME="$TMPDIR"
          export GIT_CONFIG_NOSYSTEM=1
          git -C "$REPO" init -q
          git -C "$REPO" config user.email "ci@test"
          git -C "$REPO" config user.name "CI"
          git -C "$REPO" commit --allow-empty -m "init" -q

          cd "$REPO"

          ${dartScript}
          test -f analysis_options.yaml \
            || { echo "FAIL: analysis_options.yaml not created on first run"; exit 1; }
          test -f analysis_options.standards.yaml \
            || { echo "FAIL: analysis_options.standards.yaml not created on first run"; exit 1; }
          echo "  PASS: both files created on first run"

          cat >> analysis_options.yaml <<'OVERRIDE'

          analyzer:
            exclude:
              - example/**
          OVERRIDE

          BEFORE=$(cat analysis_options.yaml)

          ${dartScript}

          AFTER=$(cat analysis_options.yaml)
          if [ "$BEFORE" != "$AFTER" ]; then
            echo "FAIL: analysis_options.yaml was overwritten on second run"
            diff <(echo "$BEFORE") <(echo "$AFTER") || true
            exit 1
          fi
          echo "  PASS: analysis_options.yaml preserved on second run"

          grep -q "example" analysis_options.yaml \
            || { echo "FAIL: user override lost"; exit 1; }
          echo "  PASS: user overrides intact"

          echo "PASS: initialOnly files correctly preserved"
          touch $out
        '';

    test-content-dart-test-coverage = pkgs.runCommand "test-content-dart-test-coverage" { } ''
      echo "=== Checking Dart test/coverage workflow ==="

      test -f ${dartTestCoverageBundle}/.github/workflows/dart-ci.yml

      # Lint job still present
      grep -q "import_sorter" ${dartTestCoverageBundle}/.github/workflows/dart-ci.yml

      # Test job present
      grep -q "dart test" ${dartTestCoverageBundle}/.github/workflows/dart-ci.yml

      # Coverage job present with Codecov
      grep -q "codecov" ${dartTestCoverageBundle}/.github/workflows/dart-ci.yml
      grep -q "unit-tests" ${dartTestCoverageBundle}/.github/workflows/dart-ci.yml
      grep -q "lcov.info" ${dartTestCoverageBundle}/.github/workflows/dart-ci.yml

      # Uses dart SDK, not flutter
      grep -q "test_with_coverage" ${dartTestCoverageBundle}/.github/workflows/dart-ci.yml

      echo "PASS: Dart test/coverage workflow correctly generated"
      touch $out
    '';

    test-content-flutter-test-coverage = pkgs.runCommand "test-content-flutter-test-coverage" { } ''
      echo "=== Checking Flutter test/coverage workflow ==="

      test -f ${flutterTestCoverageBundle}/.github/workflows/dart-ci.yml

      # Test job present
      grep -q "flutter test" ${flutterTestCoverageBundle}/.github/workflows/dart-ci.yml

      # Coverage job uses flutter-specific command
      grep -q "flutter test --coverage" ${flutterTestCoverageBundle}/.github/workflows/dart-ci.yml
      grep -q "codecov" ${flutterTestCoverageBundle}/.github/workflows/dart-ci.yml

      echo "PASS: Flutter test/coverage workflow correctly generated"
      touch $out
    '';

    test-content-dart-minimal-lint = pkgs.runCommand "test-content-dart-minimal-lint" { } ''
      echo "=== Checking Dart minimal lint (all checks disabled) ==="

      test -f ${dartMinimalLintBundle}/.github/workflows/dart-ci.yml

      # All optional lint steps should be absent
      ! grep -q "import_sorter" ${dartMinimalLintBundle}/.github/workflows/dart-ci.yml
      ! grep -q "dependency_validator" ${dartMinimalLintBundle}/.github/workflows/dart-ci.yml
      ! grep -q "dart_code_linter" ${dartMinimalLintBundle}/.github/workflows/dart-ci.yml
      ! grep -q "translations_cleaner" ${dartMinimalLintBundle}/.github/workflows/dart-ci.yml
      ! grep -q "commented-out" ${dartMinimalLintBundle}/.github/workflows/dart-ci.yml

      # Core steps still present
      grep -q "pub get" ${dartMinimalLintBundle}/.github/workflows/dart-ci.yml
      grep -q "pubspec.lock" ${dartMinimalLintBundle}/.github/workflows/dart-ci.yml

      echo "PASS: all lint steps correctly disabled"
      touch $out
    '';

    test-content-dart-multi-package = pkgs.runCommand "test-content-dart-multi-package" { } ''
      echo "=== Checking Dart multi-package workflow ==="

      test -f ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml

      # Per-package lint jobs: both packages generate separate dart_ci jobs
      grep -q "Dart CI" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml

      # SDK package uses dart commands, app package uses flutter
      grep -q "dart pub get" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml
      grep -q "flutter pub get" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml

      # Test jobs for both packages
      grep -q "dart test" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml
      grep -q "flutter test" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml

      # Coverage only for sdk package (dart, not flutter)
      grep -q "test_with_coverage" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml
      grep -q "sdk-tests" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml
      grep -q "codecov" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml

      # Directory references for both packages
      grep -q "sdk" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml
      grep -q "example/app" ${dartMultiPackageBundle}/.github/workflows/dart-ci.yml

      echo "PASS: Dart multi-package workflow correctly generated"
      touch $out
    '';

    test-content-hookd-deploy = pkgs.runCommand "test-content-hookd-deploy" { } ''
      echo "=== Checking Hookd deploy workflow ==="

      test -f ${hookdDeployBundle}/.github/workflows/hookd-deploy.yml
      test -f ${hookdDeployBundle}/.github/workflows/hookd.py

      grep -q "Hookd Deploy" ${hookdDeployBundle}/.github/workflows/hookd-deploy.yml
      grep -q "workflow_run" ${hookdDeployBundle}/.github/workflows/hookd-deploy.yml
      grep -q "HOOKD_URL" ${hookdDeployBundle}/.github/workflows/hookd-deploy.yml
      grep -q "BASIC_AUTH_PASS" ${hookdDeployBundle}/.github/workflows/hookd-deploy.yml
      grep -q "pip install" ${hookdDeployBundle}/.github/workflows/hookd-deploy.yml

      grep -q "requests" ${hookdDeployBundle}/.github/workflows/hookd.py
      grep -q "HOOKD_URL" ${hookdDeployBundle}/.github/workflows/hookd.py
      ! grep -q "itervalues" ${hookdDeployBundle}/.github/workflows/hookd.py

      echo "PASS: Hookd deploy workflow and script correctly generated"
      touch $out
    '';

    test-content-docker-simple = pkgs.runCommand "test-content-docker-simple" { } ''
      echo "=== Checking Docker simple mode ==="

      test -f ${dockerSimpleBundle}/.github/workflows/docker.yml

      grep -q "Build & Push" ${dockerSimpleBundle}/.github/workflows/docker.yml
      ! grep -q "Multi-Arch" ${dockerSimpleBundle}/.github/workflows/docker.yml
      ! grep -q "QEMU" ${dockerSimpleBundle}/.github/workflows/docker.yml
      ! grep -q "merge" ${dockerSimpleBundle}/.github/workflows/docker.yml

      grep -q "my-simple-app" ${dockerSimpleBundle}/.github/workflows/docker.yml
      grep -q "registry.example.com" ${dockerSimpleBundle}/.github/workflows/docker.yml
      grep -q "ci-user" ${dockerSimpleBundle}/.github/workflows/docker.yml
      grep -q "VERSION" ${dockerSimpleBundle}/.github/workflows/docker.yml
      grep -q "refs/tags" ${dockerSimpleBundle}/.github/workflows/docker.yml

      echo "PASS: Docker simple mode workflow correctly generated"
      touch $out
    '';

    test-content-docker-workflow-run = pkgs.runCommand "test-content-docker-workflow-run" { } ''
      echo "=== Checking Docker workflow_run trigger ==="

      test -f ${dockerWorkflowRunBundle}/.github/workflows/docker.yml

      grep -q "workflow_run" ${dockerWorkflowRunBundle}/.github/workflows/docker.yml
      grep -q "completed" ${dockerWorkflowRunBundle}/.github/workflows/docker.yml

      echo "PASS: Docker workflow_run trigger correctly generated"
      touch $out
    '';

    test-content-review-app-workflow-run = pkgs.runCommand "test-content-review-app-workflow-run" { } ''
      echo "=== Checking review-app workflow_run mode ==="

      test -f ${reviewAppWorkflowRunBundle}/.github/workflows/review-app.yml

      grep -q "workflow_run" ${reviewAppWorkflowRunBundle}/.github/workflows/review-app.yml
      grep -q "pull_request" ${reviewAppWorkflowRunBundle}/.github/workflows/review-app.yml
      grep -q "run-id" ${reviewAppWorkflowRunBundle}/.github/workflows/review-app.yml
      grep -q "test-review" ${reviewAppWorkflowRunBundle}/.github/workflows/review-app.yml

      echo "PASS: Review app workflow_run mode correctly generated"
      touch $out
    '';

    test-content-github-pages-custom = pkgs.runCommand "test-content-github-pages-custom" { } ''
      echo "=== Checking GitHub Pages custom trigger ==="

      test -f ${githubPagesCustomBundle}/.github/workflows/github-pages.yml

      grep -q "Integration Tests" ${githubPagesCustomBundle}/.github/workflows/github-pages.yml
      grep -q "test-results" ${githubPagesCustomBundle}/.github/workflows/github-pages.yml
      grep -q "run-id" ${githubPagesCustomBundle}/.github/workflows/github-pages.yml

      echo "PASS: GitHub Pages custom trigger correctly generated"
      touch $out
    '';

    test-content-monorepo-selective = pkgs.runCommand "test-content-monorepo-selective" { } ''
      echo "=== Checking selective monorepo ==="

      test -f ${monorepoSelectiveBundle}/api/clippy.toml
      test -f ${monorepoSelectiveBundle}/api/rustfmt.toml

      test -f ${monorepoSelectiveBundle}/worker/ruff.toml

      test -f ${monorepoSelectiveBundle}/.github/dependabot.yml
      ! grep -q "cargo" ${monorepoSelectiveBundle}/.github/dependabot.yml
      grep -q "pip" ${monorepoSelectiveBundle}/.github/dependabot.yml

      echo "PASS: selective monorepo features correctly scoped"
      touch $out
    '';

    test-ci-sha-pins = pkgs.runCommand "test-ci-sha-pins" { } ''
      echo "=== Checking CI workflow uses SHA pins ==="
      grep -q "actions/checkout@[a-f0-9]\{40\}" ${rustBundle}/.github/workflows/ci.yml
      grep -q "cachix/install-nix-action@[a-f0-9]\{40\}" ${rustBundle}/.github/workflows/ci.yml
      grep -q "cachix/cachix-action@[a-f0-9]\{40\}" ${rustBundle}/.github/workflows/ci.yml
      echo "PASS: CI workflow uses SHA-pinned actions"
      touch $out
    '';

    test-no-workflow-call = pkgs.runCommand "test-no-workflow-call" { } ''
      echo "=== Checking no workflow_call references in generated workflows ==="
      if grep -rq "workflow_call" ${kitchenSinkBundle}/.github/workflows/; then
        echo "FAIL: found workflow_call reference in generated workflow:"
        grep -rl "workflow_call" ${kitchenSinkBundle}/.github/workflows/
        exit 1
      fi
      echo "PASS: no workflow_call references (fully self-contained workflows)"
      touch $out
    '';

    test-concurrency-blocks = pkgs.runCommand "test-concurrency-blocks" { } ''
      echo "=== Checking concurrency blocks in generated workflows ==="

      grep -q "cancel-in-progress" ${kitchenSinkBundle}/.github/workflows/docker.yml
      grep -q "cancel-in-progress" ${kitchenSinkBundle}/.github/workflows/docker-backend.yml
      grep -q "cancel-in-progress" ${kitchenSinkBundle}/.github/workflows/rust-ci.yml

      echo "PASS: generated workflows include concurrency blocks"
      touch $out
    '';

    test-app-add-license-headers =
      let
        minimalEval = evalConsumer "app-license-headers" scenarios.minimal;
        minimalApps = minimalEval.config.flake.apps.${system} or { };
        disabledEval = evalConsumer "app-license-headers-disabled" scenarios.disabled;
        disabledApps = disabledEval.config.flake.apps.${system} or { };
      in
      assert minimalApps ? addLicenseHeaders;
      assert !(disabledApps ? addLicenseHeaders);
      pkgs.runCommand "test-app-add-license-headers" { } ''
        echo "PASS: addLicenseHeaders app present when enabled, absent when disabled"
        touch $out
      '';

    test-reuse-toml = pkgs.runCommand "test-reuse-toml" { } ''
      echo "=== Checking REUSE.toml generation ==="

      test -f ${rustBundle}/REUSE.toml
      grep -q "version = 1" ${rustBundle}/REUSE.toml
      grep -q "Famedly GmbH" ${rustBundle}/REUSE.toml
      grep -q "AGPL-3.0-only" ${rustBundle}/REUSE.toml
      grep -q ".github/\*\*" ${rustBundle}/REUSE.toml
      echo "  PASS: REUSE.toml present with correct content"

      ! test -f ${disabledBundle}/REUSE.toml
      echo "  PASS: REUSE.toml absent when disabled"

      echo "PASS: REUSE.toml generation works correctly"
      touch $out
    '';
  };

  # ---------------------------------------------------------------------------
  # 3. Workflow Validation — actionlint
  # ---------------------------------------------------------------------------

  actionlintConfig = ./actionlint.yaml;

  mkActionlintTest =
    name: bundle:
    pkgs.runCommand "test-actionlint-${name}"
      {
        nativeBuildInputs = [ pkgs.actionlint ];
      }
      ''
        echo "=== Running actionlint for scenario '${name}' ==="
        found=0
        for f in ${bundle}/.github/workflows/*.yml; do
          echo "  checking: $(basename $f)"
          found=$((found + 1))
        done
        if [ "$found" -eq 0 ]; then
          echo "FAIL: no workflow files found"
          exit 1
        fi
        actionlint \
          -config-file ${actionlintConfig} \
          -ignore 'SC2086' \
          -ignore 'SC2046' \
          ${bundle}/.github/workflows/*.yml
        echo "PASS: $found workflow files passed actionlint"
        touch $out
      '';

  workflowValidationTests = {
    test-actionlint-rust = mkActionlintTest "rust" rustBundle;
    test-actionlint-rust-publish = mkActionlintTest "rust-publish" rustPublishBundle;
    test-actionlint-rust-backend = mkActionlintTest "rust-backend" rustBackendBundle;
    test-actionlint-dart = mkActionlintTest "dart" dartBundle;
    test-actionlint-flutter = mkActionlintTest "flutter" flutterBundle;
    test-actionlint-kitchen-sink = mkActionlintTest "kitchen-sink" kitchenSinkBundle;
    test-actionlint-docker-backend = mkActionlintTest "docker-backend" dockerBackendBundle;
    test-actionlint-docker-generic = mkActionlintTest "docker-generic" dockerGenericBundle;
    test-actionlint-ansible = mkActionlintTest "ansible" ansibleBundle;
    test-actionlint-monorepo-flutter-rust = mkActionlintTest "monorepo-flutter-rust" monorepoFlutterRustBundle;
    test-actionlint-monorepo-dart-rust-ffi = mkActionlintTest "monorepo-dart-rust-ffi" monorepoDartRustFfiBundle;
    test-actionlint-dart-test-coverage = mkActionlintTest "dart-test-coverage" dartTestCoverageBundle;
    test-actionlint-flutter-test-coverage = mkActionlintTest "flutter-test-coverage" flutterTestCoverageBundle;
    test-actionlint-dart-minimal-lint = mkActionlintTest "dart-minimal-lint" dartMinimalLintBundle;
    test-actionlint-dart-multi-package = mkActionlintTest "dart-multi-package" dartMultiPackageBundle;
    test-actionlint-hookd-deploy = mkActionlintTest "hookd-deploy" hookdDeployBundle;
    test-actionlint-docker-simple = mkActionlintTest "docker-simple" dockerSimpleBundle;
    test-actionlint-docker-workflow-run = mkActionlintTest "docker-workflow-run" dockerWorkflowRunBundle;
    test-actionlint-review-app-workflow-run = mkActionlintTest "review-app-workflow-run" reviewAppWorkflowRunBundle;
    test-actionlint-github-pages-custom = mkActionlintTest "github-pages-custom" githubPagesCustomBundle;
    test-actionlint-monorepo-selective = mkActionlintTest "monorepo-selective" monorepoSelectiveBundle;
  };

  # ---------------------------------------------------------------------------
  # 4. Template Syntax Tests
  # ---------------------------------------------------------------------------

  templateTests = {
    test-template-rust-syntax =
      pkgs.runCommand "test-template-rust-syntax"
        {
          nativeBuildInputs = [ pkgs.nix ];
        }
        ''
          nix-instantiate --parse ${../templates/rust/flake.nix} > /dev/null
          echo "PASS: Rust template is syntactically valid Nix"
          touch $out
        '';

    test-template-dart-syntax =
      pkgs.runCommand "test-template-dart-syntax"
        {
          nativeBuildInputs = [ pkgs.nix ];
        }
        ''
          nix-instantiate --parse ${../templates/dart/flake.nix} > /dev/null
          echo "PASS: Dart template is syntactically valid Nix"
          touch $out
        '';

    test-template-flutter-syntax =
      pkgs.runCommand "test-template-flutter-syntax"
        {
          nativeBuildInputs = [ pkgs.nix ];
        }
        ''
          nix-instantiate --parse ${../templates/flutter/flake.nix} > /dev/null
          echo "PASS: Flutter template is syntactically valid Nix"
          touch $out
        '';

    test-template-flutter-rust-syntax =
      pkgs.runCommand "test-template-flutter-rust-syntax"
        {
          nativeBuildInputs = [ pkgs.nix ];
        }
        ''
          nix-instantiate --parse ${../templates/flutter-rust/flake.nix} > /dev/null
          echo "PASS: Flutter+Rust monorepo template is syntactically valid Nix"
          touch $out
        '';
  };

  sdkTests = {
    # Verify sdk-versions.nix has expected structure and non-empty hashes.
    test-sdk-versions-structure = pkgs.runCommand "test-sdk-versions-structure" { } (
      let
        versions = import ../sdk-versions.nix;
      in
      ''
        echo "=== Checking sdk-versions.nix structure ==="

        echo "  Dart version: ${versions.dart.version}"
        echo "  Flutter version: ${versions.flutter.version}"

        # Verify all expected platform hashes are present and non-empty
        ${lib.concatMapStrings
          (sys: ''
            [[ -n "${versions.dart.hashes.${sys}}" ]] \
              || (echo "FAIL: dart.hashes.${sys} is empty" && exit 1)
            echo "  dart.${sys}: ${versions.dart.hashes.${sys}}"
          '')
          [
            "x86_64-linux"
            "aarch64-linux"
            "x86_64-darwin"
            "aarch64-darwin"
          ]
        }

        ${lib.concatMapStrings
          (sys: ''
            [[ -n "${versions.flutter.hashes.${sys}}" ]] \
              || (echo "FAIL: flutter.hashes.${sys} is empty" && exit 1)
            echo "  flutter.${sys}: ${versions.flutter.hashes.${sys}}"
          '')
          [
            "x86_64-linux"
            "x86_64-darwin"
            "aarch64-darwin"
          ]
        }

        echo "PASS: sdk-versions.nix is well-formed"
        touch $out
      ''
    );

    # Verify the module exposes famedly-dart-sdk as a derivation.
    test-sdk-packages-exposed =
      let
        eval = evalConsumer "sdk-packages" {
          famedly.standards = {
            dart.enable = true;
            linting.rust = true;
          };
        };
        perSystemCfg = eval.config.flake.packages.${system} or { };
      in
      pkgs.runCommand "test-sdk-packages-exposed" { } ''
        echo "=== Checking SDK packages are exposed in perSystem.packages ==="

        ${
          if perSystemCfg ? famedly-dart-sdk then
            "echo '  famedly-dart-sdk: exposed (drv path: ${perSystemCfg.famedly-dart-sdk})'"
          else
            "echo 'FAIL: famedly-dart-sdk not in perSystem.packages' && exit 1"
        }

        echo "PASS: SDK packages exposed correctly"
        touch $out
      '';

    # Verify the Dart CI workflow installs the pinned SDK from the consumer flake
    # (via nix profile install .#famedly-{dart,flutter}-sdk) instead of nixpkgs.
    test-dart-ci-uses-pinned-sdk = pkgs.runCommand "test-dart-ci-uses-pinned-sdk" { } ''
      echo "=== Checking Dart CI workflow installs pinned SDK ==="

      wf=${dartBundle}/.github/workflows/dart-ci.yml

      # The workflow installs either .#famedly-dart-sdk or .#famedly-flutter-sdk
      grep -qF "nix profile install .#famedly-" "$wf" \
        || (echo "FAIL: dart-ci.yml does not use 'nix profile install .#famedly-*'" && exit 1)

      # Ensure old nixpkgs-based install is gone
      ! grep -q "nix profile install.*nixpkgs" "$wf" \
        || (echo "FAIL: dart-ci.yml still uses nixpkgs-based dart install" && exit 1)

      echo "PASS: dart-ci.yml uses pinned SDK from consumer flake"
      touch $out
    '';

    # Verify the Rust CI workflow uses dtolnay/rust-toolchain (not a container).
    test-rust-ci-uses-toolchain-action = pkgs.runCommand "test-rust-ci-uses-toolchain-action" { } ''
      echo "=== Checking Rust CI workflow uses dtolnay/rust-toolchain ==="

      wf=${rustBundle}/.github/workflows/rust-ci.yml

      grep -q "dtolnay/rust-toolchain" "$wf" \
        || (echo "FAIL: rust-ci.yml does not use dtolnay/rust-toolchain" && exit 1)

      # Default: no container when container = null
      ! grep -q "^    container:" "$wf" \
        || (echo "FAIL: rust-ci.yml has a container key but container should be null" && exit 1)

      echo "PASS: rust-ci.yml uses dtolnay/rust-toolchain action"
      touch $out
    '';
  };

in
evalTests // contentTests // workflowValidationTests // templateTests // sdkTests
