{
  description = "Famedly Engineering Standards — Nix-first standards distribution";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ./nix/modules ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Expose the standards module for consumer repos to import.
      #
      # Consumer repos add this to their flake.nix:
      #   imports = [ inputs.engineering-standards.flakeModules.default ];
      #
      # Then configure:
      #   famedly.standards.rules.enable = true;
      #   famedly.standards.linting.rust = true;
      #   etc.
      flake.flakeModules.default = ./nix/modules;

      # Nix flake templates for quick bootstrapping.
      #
      # Usage in a new repo:
      #   nix flake init -t github:famedly/engineering-standards#rust
      #   nix flake init -t github:famedly/engineering-standards#dart
      #   nix flake init -t github:famedly/engineering-standards#flutter
      #
      # Then:
      #   1. Edit flake.nix — set the description
      #   2. nix flake update
      #   3. nix run .#regenerateStandards
      #   4. nix flake check
      flake.templates = {
        rust = {
          path = ./nix/templates/rust;
          description = "Famedly Rust repo template (crane + fenix + engineering-standards)";
          welcomeText = ''
            # Famedly Rust Template

            Next steps:
              1. Edit flake.nix — replace REPLACE_WITH_REPO_DESCRIPTION
              2. nix flake update
              3. nix run .#regenerateStandards   # writes managed files
              4. nix flake check                 # runs all quality checks
              5. Commit + push → CI is just "nix flake check"
          '';
        };
        dart = {
          path = ./nix/templates/dart;
          description = "Famedly Dart repo template (engineering-standards)";
          welcomeText = ''
            # Famedly Dart Template

            Next steps:
              1. Edit flake.nix — replace REPLACE_WITH_REPO_DESCRIPTION
              2. nix flake update
              3. nix run .#regenerateStandards
              4. nix flake check
          '';
        };
        flutter = {
          path = ./nix/templates/flutter;
          description = "Famedly Flutter repo template (engineering-standards)";
          welcomeText = ''
            # Famedly Flutter Template

            Next steps:
              1. Edit flake.nix — replace REPLACE_WITH_REPO_DESCRIPTION
              2. nix flake update
              3. nix run .#regenerateStandards
              4. nix flake check
          '';
        };
        flutter-rust = {
          path = ./nix/templates/flutter-rust;
          description = "Famedly Flutter + Rust monorepo template (engineering-standards)";
          welcomeText = ''
            # Famedly Flutter + Rust Monorepo Template

            Next steps:
              1. Edit flake.nix — replace REPLACE_WITH_REPO_DESCRIPTION
              2. Create frontend/ and backend/ directories with your projects
              3. nix flake update
              4. nix run .#regenerateStandards   # writes managed files to each project dir
              5. nix flake check
          '';
        };
        default = {
          path = ./nix/templates/rust;
          description = "Famedly Rust repo template (default)";
        };
      };

      perSystem =
        {
          config,
          pkgs,
          lib,
          system,
          ...
        }:
        let
          workflows = import ./nix/reusable-workflows.nix { inherit pkgs lib; };
          engineering-standards-app = import ./nix/app-package.nix { inherit pkgs lib; };
          managed = config.famedly.standards._internal.managedFiles or [ ];
          writeManagedSnippet = lib.concatStringsSep "\n" (
            map (entry: ''
              echo "  Writing ${entry.dest}"
              _dest="${entry.dest}"
              mkdir -p "$REPO_ROOT/$(dirname "$_dest")"
              cp -f ${entry.src} "$REPO_ROOT/$_dest"
              chmod u+w "$REPO_ROOT/$_dest"
            '') managed
          );
          compositeRegen = pkgs.writeShellApplication {
            name = "regenerateStandards";
            text = ''
              set -euo pipefail
              REPO_ROOT=$(git rev-parse --show-toplevel)
              echo "Regenerating engineering-standards (flake module + nix/workflow-sources)"
              ${writeManagedSnippet}
              ${lib.getExe workflows.script}
              echo "Done. Review: git status"
            '';
          };
          ciManaged = lib.findFirst (e: e.dest == ".github/workflows/ci.yml") null managed;
        in
        {
          # Dogfood: same `famedly.standards.ci` as consumers; do not regenerate root editorconfig/dependabot here.
          famedly.standards = {
            infrastructure.editorconfig = false;
            infrastructure.dependabot = false;
            ci.enable = true;
          };

          packages.engineering-standards-app = engineering-standards-app;
          # Development shell for working on engineering-standards itself.
          devShells.default = pkgs.mkShell {
            name = "engineering-standards-dev";
            packages = with pkgs; [
              nil # Nix LSP
              nixfmt
              nodePackages.prettier
            ];
          };

          apps.regenerateStandards = lib.mkForce {
            type = "app";
            meta.description = "Regenerate ci.yml (flake module) + reusable workflows from nix/workflow-sources";
            program = lib.getExe compositeRegen;
          };

          apps.regenerateWorkflows = {
            type = "app";
            meta.description = "Alias of regenerateStandards";
            program = lib.getExe compositeRegen;
          };

          # Format check: all .nix files must be formatted with nixfmt.
          checks = {
            # Rust app (clippy + tests) — keeps CI a single `nix flake check` job (see ci-workflow.nix).
            engineering-standards-app = engineering-standards-app;

            nixfmt = pkgs.runCommand "check-nixfmt" { } ''
              ${lib.getExe pkgs.nixfmt} --check \
                $(find ${./.}/nix -name "*.nix") \
                ${./flake.nix}
              touch $out
            '';

            # Syntax-only: catches malformed Nix before module evaluation tests run.
            nix-modules-parse =
              pkgs.runCommand "check-nix-modules-parse"
                {
                  nativeBuildInputs = [ pkgs.nix ];
                }
                ''
                  set -euo pipefail
                  echo "=== nix-instantiate --parse on nix/modules/**/*.nix ==="
                  while IFS= read -r f; do
                    echo "  $f"
                    nix-instantiate --parse "$f" > /dev/null
                  done < <(find ${./nix/modules} -name '*.nix' -type f | sort)
                  echo "PASS: all flake module files parse"
                  touch $out
                '';

            workflow-consistency = pkgs.runCommand "check-workflow-consistency" { } ''
              echo "=== Checking .github/workflows/ matches generated output ==="
              failed=0
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: src: ''
                  if ! diff -q ${src} ${./.github/workflows}/${name} > /dev/null 2>&1; then
                    echo "FAIL: .github/workflows/${name} is out of date"
                    diff -u ${src} ${./.github/workflows}/${name} || true
                    failed=1
                  fi
                '') workflows.files
              )}
              if [ "$failed" -ne 0 ]; then
                echo ""
                echo "Fix: nix run .#regenerateStandards"
                exit 1
              fi
              echo "PASS: all workflow files match generated output"
              touch $out
            '';

            ci-workflow-dogfood =
              assert ciManaged != null;
              pkgs.runCommand "check-ci-workflow-dogfood" { } ''
                echo "=== Checking .github/workflows/ci.yml matches famedly.standards.ci ==="
                if ! diff -q ${ciManaged.src} ${./.github/workflows/ci.yml} > /dev/null 2>&1; then
                  echo "FAIL: ci.yml does not match flake module output"
                  diff -u ${ciManaged.src} ${./.github/workflows/ci.yml} || true
                  echo "Fix: nix run .#regenerateStandards"
                  exit 1
                fi
                echo "PASS: ci.yml is dogfooded from nix/modules/ci-workflow.nix"
                touch $out
              '';
          }
          // (import ./nix/tests {
            inherit
              inputs
              pkgs
              lib
              system
              ;
          });
        };
    };
}
