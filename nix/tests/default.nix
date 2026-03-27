# E2E test suite for engineering-standards modules.
#
# Tests verify that:
#   1. Module evaluation succeeds for realistic consumer configurations
#   2. Expected managed files are generated (presence, content, scoping)
#   2b. Repo reusable workflows: workflow-sources ↔ reusable-workflows.nix parity,
#       every @token@ defined in action-versions-data.nix, no leftover placeholders
#   3. Negative tests: disabled features produce no files
#   4. Consumer bundles + committed .github/workflows + Nix-generated YAML pass actionlint
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
  # Reusable workflow YAML as built by nix/reusable-workflows.nix (templates + pins).
  repoWorkflows = import ../reusable-workflows.nix { inherit pkgs lib; };
  workflowPins = import ../action-versions-data.nix;
  workflowSourcesDir = ../workflow-sources;
  workflowSourceFileNames = lib.sort lib.lessThan (
    builtins.attrNames (lib.filterAttrs (_: t: t == "regular") (builtins.readDir workflowSourcesDir))
  );
  generatedWorkflowFileNames = lib.sort lib.lessThan (builtins.attrNames repoWorkflows.files);

  # Dummy self for consumer simulation — checks.nix uses self.outPath
  # to point at the consumer source tree, and flake-parts accesses
  # self.inputs for per-system module evaluation.
  dummySelf = {
    outPath = pkgs.emptyDirectory;
    inherit inputs;
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
        imports = [ ../modules ];
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
            imports = [ ../modules ];
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
  # Test Scenarios — realistic consumer configurations
  # ---------------------------------------------------------------------------

  scenarios = {
    disabled = { };

    minimal = {
      famedly.standards = {
        rules.enable = true;
        checks.enable = true;
      };
    };

    # Typical Rust project (mirrors rust template)
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
        hooks = {
          enable = true;
          rust = true;
        };
        checks.enable = true;
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotRust = true;
        };
        ci = {
          enable = true;
          armRunners = true;
        };
        devShell.enable = true;
        workflows = {
          conventionalCommits = true;
          authenticateCommits = true;
          rustCi.enable = true;
        };
      };
    };

    # Rust project with crate publishing
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
        checks.enable = true;
        ci.enable = true;
        workflows = {
          conventionalCommits = true;
          rustPublish.enable = true;
        };
      };
    };

    # Rust backend project (mirrors backend repo config from design doc)
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
        hooks = {
          enable = true;
          rust = true;
        };
        checks.enable = true;
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotRust = true;
        };
        ci.enable = true;
        workflows = {
          conventionalCommits = true;
          authenticateCommits = true;
          rustCi.enable = true;
          rustPublish.enable = true;
          dockerBackend = {
            enable = true;
            targets = "backend-service";
          };
          fastForward = true;
          addToProject = {
            enable = true;
            projectUrl = "https://github.com/orgs/famedly/projects/50";
          };
        };
      };
    };

    # Typical Dart project (mirrors dart template)
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
        hooks = {
          enable = true;
          dart = true;
        };
        checks.enable = true;
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotDart = true;
        };
        ci = {
          enable = true;
          armRunners = true;
        };
        devShell.enable = true;
        dart = {
          enable = true;
          flutter = false;
        };
        workflows = {
          conventionalCommits = true;
          dartCi.enable = true;
        };
      };
    };

    # Flutter project (mirrors flutter template)
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
        hooks = {
          enable = true;
          dart = true;
        };
        checks.enable = true;
        infrastructure = {
          editorconfig = true;
          dependabot = true;
          dependabotDart = true;
        };
        ci.enable = true;
        devShell.enable = true;
        dart = {
          enable = true;
          flutter = true;
        };
        workflows = {
          conventionalCommits = true;
          authenticateCommits = true;
          dartCi.enable = true;
          dartPublish.enable = true;
          dartReviewApp = {
            enable = true;
            projectName = "test-app";
          };
          docker.enable = true;
          githubPages.enable = true;
        };
      };
    };

    # Docker backend project
    docker-backend = {
      famedly.standards = {
        ci.enable = true;
        workflows.dockerBackend = {
          enable = true;
          targets = "my-service";
        };
      };
    };

    # Docker generic project
    docker-generic = {
      famedly.standards = {
        ci.enable = true;
        workflows.docker = {
          enable = true;
          imageName = "my-app";
        };
      };
    };

    # Ansible project
    ansible = {
      famedly.standards = {
        ci.enable = true;
        workflows.ansible = {
          enable = true;
          collection = "famedly.dns";
        };
      };
    };

    # Monorepo: Flutter frontend + Rust backend using projects
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
        checks.enable = true;
        ci = {
          enable = true;
          armRunners = true;
        };
        infrastructure = {
          editorconfig = true;
          dependabot = true;
        };
        hooks.enable = true;
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
        workflows = {
          conventionalCommits = true;
          dartCi = {
            enable = true;
            directory = "frontend";
          };
        };
      };
    };

    # Monorepo: Dart at root + Rust FFI in subdirectory
    monorepo-dart-rust-ffi = {
      famedly.standards = {
        rules = {
          enable = true;
          extraScopes = [
            "dart"
            "rust"
          ];
        };
        checks.enable = true;
        ci.enable = true;
        infrastructure = {
          editorconfig = true;
          dependabot = true;
        };
        hooks.enable = true;
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
    };

    # Monorepo: projects with selective feature disabling
    monorepo-selective = {
      famedly.standards = {
        ci.enable = true;
        infrastructure.dependabot = true;
        hooks.enable = true;
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
    };

    # Everything enabled — stress test for module interactions
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
        hooks = {
          enable = true;
          rust = true;
          dart = true;
          python = true;
        };
        checks.enable = true;
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
        ci = {
          enable = true;
          armRunners = true;
        };
        devShell.enable = true;
        workflows = {
          conventionalCommits = true;
          authenticateCommits = true;
          fastForward = true;
          addToProject = {
            enable = true;
            projectUrl = "https://github.com/orgs/famedly/projects/42";
          };
          updateOpenpgpPolicy = {
            enable = true;
            teams = ''["backend"]'';
          };
          rustCi.enable = true;
          rustPublish.enable = true;
          dartCi.enable = true;
          dartPublish.enable = true;
          dartReviewApp = {
            enable = true;
            projectName = "test-app";
            environment = "review";
          };
          dockerBackend = {
            enable = true;
            targets = "svc-a,svc-b";
          };
          docker = {
            enable = true;
            imageName = "my-app";
            registry = "ghcr.io";
          };
          githubPages = {
            enable = true;
            artifactName = "docs";
          };
          ansible = {
            enable = true;
            collection = "famedly.test";
          };
        };
      };
    };
  };

  # ---------------------------------------------------------------------------
  # 1. Evaluation Tests — verify modules evaluate without errors
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
  # 2. Content Tests — verify expected managed files are generated
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
  disabledBundle = evalWithBundle "disabled" scenarios.disabled;

  # Evals used by regenerateStandards script tests.
  # evalConsumer (not evalWithBundle) is used because we need the apps output,
  # not the managed-files bundle.
  disabledScriptEval = evalConsumer "script-test-disabled" scenarios.disabled;
  disabledScript = disabledScriptEval.config.flake.apps.${system}.regenerateStandards.program;

  minimalScriptEval = evalConsumer "script-test-minimal" scenarios.minimal;
  minimalScript = minimalScriptEval.config.flake.apps.${system}.regenerateStandards.program;

  dartScriptEval = evalConsumer "script-test-dart" scenarios.dart-full;
  dartScript = dartScriptEval.config.flake.apps.${system}.regenerateStandards.program;

  allowedWorkflowPinNamesFile = pkgs.writeText "allowed-workflow-pins" (
    lib.concatStringsSep "\n" (lib.sort lib.lessThan (builtins.attrNames workflowPins))
  );

  contentTests = {
    test-content-rust = pkgs.runCommand "test-content-rust" { } ''
      echo "=== Checking Rust consumer managed files ==="

      # CI workflow
      test -f ${rustBundle}/.github/workflows/ci.yml
      grep -q "arm-ubuntu-latest" ${rustBundle}/.github/workflows/ci.yml

      # Rust CI workflow (must reference floating major tag, not @main)
      test -f ${rustBundle}/.github/workflows/rust-ci.yml
      grep -q "rust-ci.yml@v1" ${rustBundle}/.github/workflows/rust-ci.yml

      # Conventional commits + authenticate commits
      test -f ${rustBundle}/.github/workflows/general-checks.yml
      test -f ${rustBundle}/.github/workflows/authenticate-commits.yml

      # Infrastructure
      test -f ${rustBundle}/.editorconfig
      test -f ${rustBundle}/.github/dependabot.yml
      grep -q "cargo" ${rustBundle}/.github/dependabot.yml

      # Hooks
      test -f ${rustBundle}/.pre-commit-config.yaml

      # Linting configs
      test -f ${rustBundle}/clippy.toml
      test -f ${rustBundle}/rustfmt.toml

      # AI rules
      test -f ${rustBundle}/CLAUDE.md
      test -d ${rustBundle}/.cursor/rules/standards

      echo "PASS: all expected Rust managed files present and correct"
      touch $out
    '';

    test-content-rust-backend = pkgs.runCommand "test-content-rust-backend" { } ''
      echo "=== Checking Rust backend consumer managed files ==="

      # CI workflows
      test -f ${rustBackendBundle}/.github/workflows/ci.yml
      test -f ${rustBackendBundle}/.github/workflows/rust-ci.yml
      test -f ${rustBackendBundle}/.github/workflows/publish-crate.yml
      test -f ${rustBackendBundle}/.github/workflows/docker-backend.yml

      # General workflows
      test -f ${rustBackendBundle}/.github/workflows/general-checks.yml
      test -f ${rustBackendBundle}/.github/workflows/authenticate-commits.yml
      test -f ${rustBackendBundle}/.github/workflows/fast-forward.yml
      test -f ${rustBackendBundle}/.github/workflows/add-to-project.yml

      # Fast-forward contains correct trigger
      grep -q "issue_comment" ${rustBackendBundle}/.github/workflows/fast-forward.yml

      # Docker backend targets correct service
      grep -q "backend-service" ${rustBackendBundle}/.github/workflows/docker-backend.yml

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
      test -f ${dartBundle}/.pre-commit-config.yaml
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
      test -f ${flutterBundle}/.pre-commit-config.yaml
      test -f ${flutterBundle}/.editorconfig
      test -f ${flutterBundle}/CLAUDE.md

      # GitHub Pages uses deploy-pages API (permissions block in caller)
      grep -q "pages: write" ${flutterBundle}/.github/workflows/github-pages.yml

      # Review app
      test -f ${flutterBundle}/.github/workflows/review-app.yml

      echo "PASS: all expected Flutter managed files present and correct"
      touch $out
    '';

    test-content-kitchen-sink = pkgs.runCommand "test-content-kitchen-sink" { } ''
      echo "=== Checking kitchen-sink consumer managed files ==="

      # All workflow files
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

      # Infrastructure
      test -f ${kitchenSinkBundle}/.editorconfig
      test -f ${kitchenSinkBundle}/.github/dependabot.yml
      test -f ${kitchenSinkBundle}/.pre-commit-config.yaml
      test -f ${kitchenSinkBundle}/CLAUDE.md

      # All dependabot ecosystems
      grep -q "cargo"     ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "pub"       ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "pip"       ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "docker"    ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "npm"       ${kitchenSinkBundle}/.github/dependabot.yml
      grep -q "terraform" ${kitchenSinkBundle}/.github/dependabot.yml

      # CI uses ARM runners
      grep -q "arm-ubuntu-latest" ${kitchenSinkBundle}/.github/workflows/ci.yml

      echo "PASS: all expected kitchen-sink managed files present and correct"
      touch $out
    '';

    # Monorepo: Flutter + Rust — linting files in subdirectories
    test-content-monorepo-flutter-rust = pkgs.runCommand "test-content-monorepo-flutter-rust" { } ''
      echo "=== Checking Flutter+Rust monorepo managed files ==="

      # Rust linting configs in backend/
      test -f ${monorepoFlutterRustBundle}/backend/clippy.toml
      test -f ${monorepoFlutterRustBundle}/backend/rustfmt.toml
      test -f ${monorepoFlutterRustBundle}/backend/deny.toml

      # Flutter linting config in frontend/
      test -f ${monorepoFlutterRustBundle}/frontend/analysis_options.yaml
      test -f ${monorepoFlutterRustBundle}/frontend/analysis_options.standards.yaml

      # Rust configs should NOT be at root
      ! test -f ${monorepoFlutterRustBundle}/clippy.toml
      ! test -f ${monorepoFlutterRustBundle}/rustfmt.toml

      # Flutter config should NOT be at root
      ! test -f ${monorepoFlutterRustBundle}/analysis_options.yaml

      # Dependabot should have both ecosystems with correct directories
      test -f ${monorepoFlutterRustBundle}/.github/dependabot.yml
      grep -q "cargo" ${monorepoFlutterRustBundle}/.github/dependabot.yml
      grep -q "pub" ${monorepoFlutterRustBundle}/.github/dependabot.yml
      grep -q "/backend" ${monorepoFlutterRustBundle}/.github/dependabot.yml
      grep -q "/frontend" ${monorepoFlutterRustBundle}/.github/dependabot.yml

      # Pre-commit hooks should exist and reference directories
      test -f ${monorepoFlutterRustBundle}/.pre-commit-config.yaml
      grep -q "backend" ${monorepoFlutterRustBundle}/.pre-commit-config.yaml
      grep -q "frontend" ${monorepoFlutterRustBundle}/.pre-commit-config.yaml

      # Standard files should still be at root
      test -f ${monorepoFlutterRustBundle}/.editorconfig
      test -f ${monorepoFlutterRustBundle}/.github/workflows/ci.yml
      test -f ${monorepoFlutterRustBundle}/CLAUDE.md

      echo "PASS: monorepo Flutter+Rust managed files correctly scoped"
      touch $out
    '';

    # Monorepo: Dart at root + Rust FFI in subdirectory
    test-content-monorepo-dart-rust-ffi = pkgs.runCommand "test-content-monorepo-dart-rust-ffi" { } ''
      echo "=== Checking Dart+Rust FFI monorepo managed files ==="

      # Dart config at root (directory = "")
      test -f ${monorepoDartRustFfiBundle}/analysis_options.yaml

      # Rust configs in rust/
      test -f ${monorepoDartRustFfiBundle}/rust/clippy.toml
      test -f ${monorepoDartRustFfiBundle}/rust/rustfmt.toml

      # Dependabot with correct directories
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

    # Negative test: nothing explicitly enabled → only default-on files
    test-negative-disabled = pkgs.runCommand "test-negative-disabled" { } ''
      echo "=== Checking disabled scenario only produces defaults ==="

      # These default to true and are expected
      test -f ${disabledBundle}/.editorconfig
      test -f ${disabledBundle}/.github/dependabot.yml

      # Nothing else should exist — no workflows, hooks, linting, rules
      ! test -d ${disabledBundle}/.github/workflows
      ! test -f ${disabledBundle}/.pre-commit-config.yaml
      ! test -f ${disabledBundle}/CLAUDE.md
      ! test -f ${disabledBundle}/clippy.toml
      ! test -f ${disabledBundle}/analysis_options.yaml

      # Total: exactly 2 files
      count=$(find ${disabledBundle} -type f | wc -l)
      if [ "$count" -ne 2 ]; then
        echo "FAIL: expected exactly 2 default files, got $count:"
        find ${disabledBundle} -type f
        exit 1
      fi

      echo "PASS: disabled scenario produces only default infrastructure files"
      touch $out
    '';

    # Verify that regenerateStandards writes a manifest listing all managed files.
    # Uses the minimal scenario (rules + checks enabled) as a realistic case.
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

          # All file operations use relative paths after cd (see test-manifest-cleanup
          # for the rationale: avoids symlink mismatches with git rev-parse).
          cd "$REPO"
          ${minimalScript}

          MANIFEST=".engineering-standards-manifest"
          test -f "$MANIFEST" || { echo "FAIL: manifest not written"; exit 1; }

          # Minimal scenario enables rules → CLAUDE.md and cursor rules must appear
          grep -q "CLAUDE.md" "$MANIFEST" \
            || { echo "FAIL: CLAUDE.md missing from manifest"; exit 1; }
          grep -q ".cursor/rules/standards" "$MANIFEST" \
            || { echo "FAIL: .cursor/rules/standards missing from manifest"; exit 1; }

          # Every line in the manifest must correspond to an actual file on disk
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

    # Verify that regenerateStandards removes files from a previous generation
    # when they are no longer in managedFiles (e.g. after disabling a feature).
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

          # All file operations use relative paths after cd to avoid symlink
          # mismatches between mktemp output and git rev-parse --show-toplevel
          # output (the script resolves symlinks internally via git).
          cd "$REPO"

          # Simulate a previous generation where rules were enabled.
          mkdir -p .cursor/rules/standards
          echo "stale rule content" > .cursor/rules/standards/stale.md
          echo "stale CLAUDE" > CLAUDE.md
          # Old manifest includes both the stale files and the still-current defaults.
          printf '.cursor/rules/standards/stale.md\nCLAUDE.md\n.editorconfig\n.github/dependabot.yml\n' \
            > .engineering-standards-manifest

          # Run the disabled scenario (rules.enable = false → no rules in managedFiles).
          ${disabledScript}

          # Stale files must be gone.
          if test -f .cursor/rules/standards/stale.md; then
            echo "FAIL: stale .cursor/rules/standards/stale.md was not removed"
            exit 1
          fi
          if test -f CLAUDE.md; then
            echo "FAIL: stale CLAUDE.md was not removed"
            exit 1
          fi
          echo "  PASS: stale rule files removed"

          # Default infrastructure files must still be present (re-written by script).
          test -f .editorconfig \
            || { echo "FAIL: .editorconfig missing after cleanup"; exit 1; }
          test -f .github/dependabot.yml \
            || { echo "FAIL: .github/dependabot.yml missing after cleanup"; exit 1; }
          echo "  PASS: default infrastructure files still present"

          # Manifest must now contain only the currently managed files.
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

    # Verify that initialOnly files are not overwritten on subsequent runs.
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

          # First run: both files should be created.
          ${dartScript}
          test -f analysis_options.yaml \
            || { echo "FAIL: analysis_options.yaml not created on first run"; exit 1; }
          test -f analysis_options.standards.yaml \
            || { echo "FAIL: analysis_options.standards.yaml not created on first run"; exit 1; }
          echo "  PASS: both files created on first run"

          # Simulate user adding overrides to analysis_options.yaml.
          cat >> analysis_options.yaml <<'OVERRIDE'

          analyzer:
            exclude:
              - example/**
          OVERRIDE

          BEFORE=$(cat analysis_options.yaml)

          # Second run: analysis_options.yaml must be untouched,
          # analysis_options.standards.yaml must be overwritten.
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

    # Verify all generated consumer workflows carry the managed-by marker
    test-managed-by-headers = pkgs.runCommand "test-managed-by-headers" { } ''
      echo "=== Checking managed-by headers ==="
      failed=0
      for f in ${kitchenSinkBundle}/.github/workflows/*.yml; do
        if ! grep -q "managed-by: engineering-standards" "$f"; then
          echo "FAIL: $(basename $f) missing managed-by header"
          failed=1
        fi
      done
      if [ "$failed" -ne 0 ]; then exit 1; fi
      echo "PASS: all generated workflows have managed-by headers"
      touch $out
    '';

    # Selective monorepo: per-project feature toggling
    test-content-monorepo-selective = pkgs.runCommand "test-content-monorepo-selective" { } ''
      echo "=== Checking selective monorepo ==="

      # api (rust, dependabot=false) — linting present, no cargo in dependabot
      test -f ${monorepoSelectiveBundle}/api/clippy.toml
      test -f ${monorepoSelectiveBundle}/api/rustfmt.toml

      # worker (python, hooks=false) — linting present
      test -f ${monorepoSelectiveBundle}/worker/ruff.toml

      # Dependabot: should exist but NOT contain cargo (api disabled it)
      test -f ${monorepoSelectiveBundle}/.github/dependabot.yml
      ! grep -q "cargo" ${monorepoSelectiveBundle}/.github/dependabot.yml
      grep -q "pip" ${monorepoSelectiveBundle}/.github/dependabot.yml

      # Hooks: should exist but NOT reference worker (hooks=false)
      test -f ${monorepoSelectiveBundle}/.pre-commit-config.yaml
      ! grep -q "worker" ${monorepoSelectiveBundle}/.pre-commit-config.yaml

      echo "PASS: selective monorepo features correctly scoped"
      touch $out
    '';

    # Verify CI workflow uses SHA pins from action-versions
    test-ci-sha-pins = pkgs.runCommand "test-ci-sha-pins" { } ''
      echo "=== Checking CI workflow uses SHA pins ==="
      grep -q "actions/checkout@[a-f0-9]\{40\}" ${rustBundle}/.github/workflows/ci.yml
      grep -q "cachix/install-nix-action@[a-f0-9]\{40\}" ${rustBundle}/.github/workflows/ci.yml
      grep -q "cachix/cachix-action@[a-f0-9]\{40\}" ${rustBundle}/.github/workflows/ci.yml
      echo "PASS: CI workflow uses SHA-pinned actions"
      touch $out
    '';

    # Verify ALL generated callers reference @v1 (not @main)
    test-workflow-ref = pkgs.runCommand "test-workflow-ref" { } ''
      echo "=== Checking workflowRef propagation in all callers ==="
      failed=0
      for f in ${kitchenSinkBundle}/.github/workflows/*.yml; do
        name=$(basename "$f")
        # Skip non-caller workflows (CI, update workflows are self-contained)
        case "$name" in ci.yml|update-*) continue ;; esac
        if grep -q "@main" "$f"; then
          echo "FAIL: $name still references @main"
          failed=1
        fi
        if grep -q "famedly/engineering-standards/" "$f" && ! grep -q "@v1" "$f"; then
          echo "FAIL: $name does not reference @v1"
          failed=1
        fi
      done
      if [ "$failed" -ne 0 ]; then exit 1; fi
      echo "PASS: all generated callers use @v1"
      touch $out
    '';

    # Verify workflowRef override works (e.g. for testing feature branches)
    test-workflow-ref-override =
      let
        overrideBundle = evalWithBundle "ref-override" {
          famedly.standards = {
            workflowRef = "feat/my-branch";
            ci.enable = true;
            workflows = {
              conventionalCommits = true;
              rustCi.enable = true;
              dartCi.enable = true;
              ansible = {
                enable = true;
                collection = "famedly.test";
              };
            };
          };
        };
      in
      pkgs.runCommand "test-workflow-ref-override" { } ''
        echo "=== Checking workflowRef override ==="
        grep -q "@feat/my-branch" ${overrideBundle}/.github/workflows/general-checks.yml
        grep -q "@feat/my-branch" ${overrideBundle}/.github/workflows/rust-ci.yml
        grep -q "@feat/my-branch" ${overrideBundle}/.github/workflows/dart-ci.yml
        grep -q "@feat/my-branch" ${overrideBundle}/.github/workflows/ansible-ci.yml
        ! grep -q "@main" ${overrideBundle}/.github/workflows/general-checks.yml
        ! grep -q "@v1" ${overrideBundle}/.github/workflows/general-checks.yml
        echo "PASS: workflowRef override correctly propagated"
        touch $out
      '';

    # Verify concurrency blocks in generated caller workflows
    test-concurrency-blocks = pkgs.runCommand "test-concurrency-blocks" { } ''
      echo "=== Checking concurrency blocks in generated callers ==="

      # Docker callers should have concurrency
      grep -q "cancel-in-progress" ${kitchenSinkBundle}/.github/workflows/docker.yml
      grep -q "cancel-in-progress" ${kitchenSinkBundle}/.github/workflows/docker-backend.yml

      # Rust CI caller should have concurrency
      grep -q "cancel-in-progress" ${kitchenSinkBundle}/.github/workflows/rust-ci.yml

      echo "PASS: generated callers include concurrency blocks"
      touch $out
    '';
  };

  # ---------------------------------------------------------------------------
  # 2b. engineering-standards repo workflows (Nix templates + pins)
  # ---------------------------------------------------------------------------

  repoWorkflowTests =
    assert workflowSourceFileNames == generatedWorkflowFileNames;
    {
      test-workflow-catalog-parity = pkgs.runCommand "test-workflow-catalog-parity" { } ''
        echo "PASS: nix/workflow-sources/ matches reusable-workflows.nix (${toString (builtins.length workflowSourceFileNames)} files)"
        touch $out
      '';

      test-workflow-template-pins-known = pkgs.runCommand "test-workflow-template-pins-known" { } ''
        set -euo pipefail
        echo "=== Checking every @token@ in nix/workflow-sources/ exists in action-versions-data.nix ==="
        shopt -s nullglob
        tpls=(${workflowSourcesDir}/*.yml)
        if [ ''${#tpls[@]} -eq 0 ]; then
          echo "FAIL: no workflow templates"
          exit 1
        fi
        while IFS= read -r token; do
          [ -z "$token" ] && continue
          name="''${token#@}"
          name="''${name%@}"
          if ! grep -qx "$name" ${allowedWorkflowPinNamesFile}; then
            echo "FAIL: placeholder $token has no entry in nix/action-versions-data.nix (expected attribute name: $name)"
            exit 1
          fi
        done < <(grep -hoE '@[a-zA-Z][a-zA-Z0-9]*@' "''${tpls[@]}" | sort -u)
        echo "PASS: all template placeholders are defined in action-versions-data.nix"
        touch $out
      '';

      test-nix-workflows-no-stray-placeholders =
        pkgs.runCommand "test-nix-workflows-no-stray-placeholders" { }
          ''
            set -euo pipefail
            echo "=== Checking Nix-generated workflows have no leftover @placeholders@ ==="
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (fname: src: ''
                if grep -qE '@[a-zA-Z][a-zA-Z0-9]*@' ${src}; then
                  echo "FAIL: unreplaced placeholders in generated ${fname}"
                  grep -nE '@[a-zA-Z][a-zA-Z0-9]*@' ${src} || true
                  exit 1
                fi
              '') repoWorkflows.files
            )}
            echo "PASS: no stray @placeholders@ in generated workflow files"
            touch $out
          '';
    };

  # ---------------------------------------------------------------------------
  # 3. Workflow Validation — actionlint checks syntax, semantics, expressions
  # ---------------------------------------------------------------------------

  actionlintConfig = ./actionlint.yaml;
  sourceWorkflows = ../../.github/workflows;

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
        actionlint -config-file ${actionlintConfig} ${bundle}/.github/workflows/*.yml
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
    test-actionlint-monorepo-selective = mkActionlintTest "monorepo-selective" monorepoSelectiveBundle;

    # Same YAML as .github/workflows/ after regenerateStandards, validated independently of git checkout.
    test-actionlint-nix-workflow-regeneration =
      pkgs.runCommand "test-actionlint-nix-workflow-regeneration"
        {
          nativeBuildInputs = [ pkgs.actionlint ];
        }
        ''
          set -euo pipefail
          echo "=== Running actionlint on Nix-substituted workflow-sources (store paths) ==="
          mkdir -p wrk
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (fname: src: "cp ${src} wrk/${fname}") repoWorkflows.files
          )}
          shopt -s nullglob
          files=(wrk/*.yml)
          count=''${#files[@]}
          if [ "$count" -eq 0 ]; then
            echo "FAIL: no generated workflow files"
            exit 1
          fi
          actionlint \
            -config-file ${actionlintConfig} \
            -ignore 'SC2086' \
            -ignore 'SC2046' \
            "''${files[@]}"
          echo "PASS: $count Nix-generated workflows passed actionlint"
          touch $out
        '';

    # Source reusable workflows (the ones consumers call via `uses:`)
    test-actionlint-source =
      pkgs.runCommand "test-actionlint-source"
        {
          nativeBuildInputs = [ pkgs.actionlint ];
        }
        ''
          echo "=== Running actionlint on source reusable workflows ==="
          found=0
          for f in ${sourceWorkflows}/*.yml; do
            echo "  checking: $(basename $f)"
            found=$((found + 1))
          done
          actionlint \
            -config-file ${actionlintConfig} \
            -ignore 'SC2086' \
            -ignore 'SC2046' \
            ${sourceWorkflows}/*.yml
          echo "PASS: $found source workflow files passed actionlint"
          touch $out
        '';
  };

  # ---------------------------------------------------------------------------
  # 4. Template Syntax Tests — verify template flake.nix files parse
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

in
evalTests // contentTests // repoWorkflowTests // workflowValidationTests // templateTests
