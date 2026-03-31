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

      dartHooksEnabled =
        (config.famedly.standards.preCommitHooks.dartHooks.enable or false) && hooksEnabled;
      projects = config.famedly.standards.projects or { };
      dartProjects = lib.filterAttrs (
        _: p: (p.language or "") == "dart" || (p.language or "") == "flutter"
      ) projects;
      hasDart = dartHooksEnabled || dartProjects != { };
      dartProjectDirs =
        lib.optionals dartHooksEnabled [ "" ] ++ lib.mapAttrsToList (_: p: p.directory or "") dartProjects;

      rustHooksEnabled =
        (config.famedly.standards.preCommitHooks.rustHooks.enable or false) && hooksEnabled;
      rustProjects = lib.filterAttrs (_: p: (p.language or "") == "rust") projects;
      hasRustHooks = rustHooksEnabled || rustProjects != { };

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
          rc=0
          if [[ "''${1:-}" == "--fix" || "''${1:-}" == "-f" ]]; then
            echo "Running pre-commit hooks (with auto-fix)..."
            pre-commit run --all-files || true
            echo ""
            echo "Done. Review the changes with: git diff"
          else
            echo "Running pre-commit hooks..."
            pre-commit run --all-files || rc=$?
          fi
        ''
        + lib.optionalString hasDart (
          let
            checks = lib.concatMapStringsSep "\n" (
              dir:
              let
                label = if dir == "" then "root" else dir;
                cmd =
                  if dir == "" then
                    "dart pub global run dependency_validator || rc=1"
                  else
                    "(cd ${dir} && dart pub global run dependency_validator) || rc=1";
              in
              "echo \"  → ${label}\"\n${cmd}"
            ) dartProjectDirs;
          in
          ''

            echo ""
            echo "Running dependency_validator..."
            if dart pub global activate dependency_validator 2>/dev/null; then
            ${checks}
            else
              echo "  ⚠ Could not activate dependency_validator — skipping."
            fi
          ''
        )
        + ''

          exit "$rc"
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

      e2eEnabled = config.famedly.standards.e2e.enable or false;

      famedly-help = pkgs.writeShellApplication {
        name = "famedly-help";
        text =
          ''
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
          ''
          + lib.optionalString e2eEnabled ''

            echo ""
            echo "e2e Testing (k3d + Argo CD):"
            echo ""
            echo "  famedly-e2e-up           Start e2e environment (registry + cluster + deploy + seed)"
            echo "  famedly-e2e-down         Delete cluster and registry"
            echo "  famedly-e2e              CI: up → test → down (atomic)"
            echo "  famedly-e2e-seed         Re-run seed script without redeploying"
            echo "  famedly-e2e-status       Show cluster, Argo, and pod status"
            echo "  famedly-e2e-logs <svc>   Tail logs for a service"
            echo ""
            echo "  Tip: famedly-e2e-down && famedly-e2e-up   — full reset"
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
        + "\n"
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
          ''
          + lib.optionalString hasRustHooks ''
            # Isolate Nix dev shell cargo artifacts from system cargo builds
            # to prevent toolchain version mismatches (different rustc fingerprints).
            export CARGO_TARGET_DIR="''${CARGO_TARGET_DIR:-$PWD/target/nix-dev}"
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
