{
  description = "Famedly Engineering Standards — Nix-first standards distribution";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    github-actions-nix = {
      url = "github:synapdeck/github-actions-nix";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        lib,
        flake-parts-lib,
        ...
      }@args:
      let
        inherit (flake-parts-lib) importApply;

        flakeModules = {
          standards = ./nix/modules;
          workflows = importApply ./nix/modules/workflows args;
          preCommitHooks = importApply ./nix/modules/pre-commit-hooks.nix args;
        };
      in
      {
        imports = lib.attrValues flakeModules;

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        flake.flakeModules = flakeModules // {
          default = {
            imports = lib.attrValues flakeModules;
          };
        };

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
            ciManaged = lib.findFirst (e: e.dest == ".github/workflows/ci.yml") null (
              config.famedly.standards._internal.managedFiles or [ ]
            );
          in
          {
            famedly.standards = {
              infrastructure.editorconfig = false;
              infrastructure.dependabot = false;
              preCommitHooks = {
                enable = true;
                fossHooks.enable = false;
              };
            };
            famedly.github.workflows.ci.enable = true;

            apps.updateSdkVersions = {
              type = "app";
              meta.description = "Update nix/sdk-versions.nix to the latest stable Dart and Flutter releases";
              program = lib.getExe (
                pkgs.writeShellApplication {
                  name = "updateSdkVersions";
                  runtimeInputs = [
                    pkgs.nix
                    pkgs.python3
                  ];
                  text = ''
                    exec python3 ${./nix/packages/update-sdk-versions.py} "$@"
                  '';
                }
              );
            };

            devShells.default = pkgs.mkShell {
              name = "engineering-standards-dev";
              packages = with pkgs; [
                nil
                nixfmt
                nodePackages.prettier
              ];
            };

            checks = {
              nixfmt = pkgs.runCommand "check-nixfmt" { } ''
                ${lib.getExe pkgs.nixfmt} --check \
                  $(find ${./.}/nix -name "*.nix") \
                  ${./flake.nix}
                touch $out
              '';

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
                  echo "PASS: ci.yml is dogfooded from nix/modules/workflows/definitions/ci.nix"
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
      }
    );
}
