# DevShell module: adds standard development tools to `nix develop`.
#
# When preCommitHooks are enabled, the devShell composes with
# git-hooks.nix's devShell which provides:
#   - shellHook to auto-install pre-commit hooks on `nix develop`
#   - all hook tool packages (typos, reuse, clippy, etc.)
#
# Language-specific toolchains (Dart SDK, Rust/fenix, etc.) are the
# responsibility of the consumer repo's own devShell configuration.
#
# Generated files in consumer repo:
#   .envrc      — direnv integration (use flake)
#   .nixd.json  — nixd language server config for option completion

{ flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.devShell;
      hooksEnabled = config.famedly.standards.preCommitHooks.enable or false;
      fossEnabled = (config.famedly.standards.preCommitHooks.fossHooks.enable or false) && hooksEnabled;

      famedly-regen = pkgs.writeShellApplication {
        name = "famedly-regen";
        text = ''
          if [[ "''${1:-}" == "--dev" || "''${1:-}" == "-d" ]]; then
            ES_PATH="''${ENGINEERING_STANDARDS_PATH:-../engineering-standards}"
            if [[ ! -d "$ES_PATH" ]]; then
              echo "Error: engineering-standards not found at $ES_PATH"
              echo "Set ENGINEERING_STANDARDS_PATH or clone next to this repo."
              exit 1
            fi
            ES_ABS="$(cd "$ES_PATH" && pwd)"
            echo "Using local engineering-standards at $ES_ABS"
            nix run --override-input engineering-standards "path:$ES_ABS" .#regenerateStandards
          elif [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
            echo "Usage: famedly-regen [--dev|-d]"
            echo ""
            echo "Regenerate engineering-standards managed files."
            echo ""
            echo "  (no flag)    Use the pinned flake.lock input"
            echo "  --dev, -d    Override with local engineering-standards"
            echo "               (defaults to ../engineering-standards,"
            echo "                set ENGINEERING_STANDARDS_PATH to override)"
          else
            nix run .#regenerateStandards
          fi
        '';
      };

      famedly-check = pkgs.writeShellApplication {
        name = "famedly-check";
        text = ''
          echo "Running nix flake check..."
          nix flake check -L "''${@}"
        '';
      };

      famedly-lint = pkgs.writeShellApplication {
        name = "famedly-lint";
        text = ''
          if [[ "''${1:-}" == "--fix" || "''${1:-}" == "-f" ]]; then
            echo "Running pre-commit hooks (with auto-fix)..."
            pre-commit run --all-files || true
            pre-commit run --all-files --hook-stage manual || true
            echo ""
            echo "Done. Review the changes with: git diff"
          else
            echo "Running pre-commit hooks..."
            pre-commit run --all-files
            pre-commit run --all-files --hook-stage manual
          fi
        '';
      };

      famedly-update = pkgs.writeShellApplication {
        name = "famedly-update";
        text = ''
          echo "==> Updating engineering-standards flake input..."
          nix flake update engineering-standards

          echo ""
          echo "==> Regenerating managed files..."
          nix run .#regenerateStandards

          echo ""
          echo "==> Running checks..."
          if nix flake check -L; then
            echo ""
            echo "All checks passed. Review and commit:"
            echo "  git add -A && git commit -m 'chore: update engineering-standards'"
          else
            echo ""
            echo "Some checks failed. Fix issues before committing."
          fi
        '';
      };

      famedly-help = pkgs.writeShellApplication {
        name = "famedly-help";
        text = ''
          echo "Famedly Engineering Standards — Developer Commands"
          echo ""
          echo "  famedly-regen [--dev]    Regenerate managed files"
          echo "  famedly-check            Run all CI checks locally (nix flake check)"
          echo "  famedly-lint [--fix]     Run pre-commit hooks on all files"
          echo "  famedly-update           Update standards, regenerate, and check"
          echo "  famedly-help             Show this help"
          echo ""
          echo "Flags:"
          echo "  famedly-regen --dev      Use local ../engineering-standards"
          echo "  famedly-lint --fix       Auto-fix and continue on errors"
          echo ""
          echo "Environment:"
          echo "  ENGINEERING_STANDARDS_PATH   Override path for --dev (default: ../engineering-standards)"
        '';
      };

      envrc = pkgs.writeText ".envrc" "use flake\n";

      nixdJson = pkgs.writeText ".nixd.json" (
        builtins.toJSON {
          nixpkgs = {
            expr = "import (builtins.getFlake (toString ./.)).inputs.nixpkgs { }";
          };
          options = {
            target = {
              installable = ".#debug.options";
            };
          };
        }
      );
    in
    {
      options.famedly.standards.devShell = {
        enable = lib.mkEnableOption "shared dev shell tools";

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional packages to add to the dev shell.";
        };
      };

      config = lib.mkIf cfg.enable {
        devShells.famedly-standards = pkgs.mkShell {
          name = "famedly-standards";
          inputsFrom = lib.optionals hooksEnabled [
            config.pre-commit.devShell
          ];
          packages = [
            famedly-regen
            famedly-check
            famedly-lint
            famedly-update
            famedly-help
            pkgs.nixd
            pkgs.nixfmt
            pkgs.nix-output-monitor
          ]
          ++ lib.optionals fossEnabled [ pkgs.reuse ]
          ++ cfg.extraPackages;
          shellHook = ''
            echo ""
            echo "  Famedly Dev Shell — type 'famedly-help' for available commands"
            echo ""
          '';
        };

        famedly.standards._internal.managedFiles = [
          {
            src = envrc;
            dest = ".envrc";
          }
          {
            src = nixdJson;
            dest = ".nixd.json";
          }
        ];
      };
    }
  );
}
