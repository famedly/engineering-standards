# Main flake module for engineering-standards.
#
# Consumer repos import this module and configure it via:
#
#   perSystem = { ... }: {
#     famedly.standards = {
#       rules.enable = true;
#       linting.rust = true;
#       checks.enable = true;
#       infrastructure.editorconfig = true;
#     };
#   };
#
# For monorepos, use the projects abstraction:
#
#   perSystem = { ... }: {
#     famedly.standards = {
#       projects.backend  = { language = "rust";    directory = "backend"; };
#       projects.frontend = { language = "flutter"; directory = "frontend"; };
#     };
#   };
#
# Then run `nix run .#regenerateStandards` to write managed files,
# and `nix flake check` to run the standard quality checks.
#
# File lifecycle: regenerateStandards maintains a manifest at
# .engineering-standards-manifest that tracks all generated files.
# When a feature is disabled, the next regenerate run automatically
# removes the files that belong to it. Commit the manifest alongside
# other generated files.

{ flake-parts-lib, lib, ... }:
let
  # Root of the engineering-standards source tree.
  # When consumed as a flake input this is the store path of the repo.
  root = ../..;
in
{
  imports = [
    ./action-versions.nix
    ./rules.nix
    ./linting.nix
    ./hooks.nix
    ./checks.nix
    ./infrastructure.nix
    ./devshell.nix
    ./ci-workflow.nix
    ./update-workflow.nix
    ./dart.nix
    ./projects.nix
    ./workflows/general.nix
    ./workflows/dart.nix
    ./workflows/rust.nix
    ./workflows/docker.nix
    ./workflows/ansible.nix
  ];

  # The regenerateStandards app collects all managed files from enabled
  # modules and writes them to the correct locations in the repository.
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, ... }:
    let
      cfg = config.famedly.standards;

      # Generate one shell snippet per managed file.
      # builtins.dirOf gives us the parent directory without bash tricks.
      fileSnippets = map (
        entry:
        let
          destDir = builtins.dirOf entry.dest;
        in
        ''
          echo "  Writing ${entry.dest}"
          mkdir -p "$REPO_ROOT/${destDir}"
          cp ${entry.src} "$REPO_ROOT/${entry.dest}"
          chmod u+w "$REPO_ROOT/${entry.dest}"
        ''
      ) cfg._internal.managedFiles;

      # Manifest tracks all currently-managed destination paths so that
      # regenerateStandards can remove files that are no longer managed
      # (e.g. after disabling a feature). The manifest is written into the
      # consumer repo and should be committed alongside other generated files.
      manifestRelPath = ".engineering-standards-manifest";
      newManifestFile = pkgs.writeText "engineering-standards-manifest" (
        lib.concatMapStrings (entry: "${entry.dest}\n") cfg._internal.managedFiles
      );

      regenerateScript = pkgs.writeShellApplication {
        name = "regenerateStandards";
        text = ''
          set -euo pipefail
          REPO_ROOT=$(git rev-parse --show-toplevel)
          MANIFEST="$REPO_ROOT/${manifestRelPath}"
          echo "Regenerating engineering-standards managed files in $REPO_ROOT"

          # Remove files from the previous generation that are no longer managed.
          if [[ -f "$MANIFEST" ]]; then
            echo "Cleaning up files no longer managed..."
            while IFS= read -r old_file; do
              [[ -z "$old_file" ]] && continue
              # Never delete the manifest itself.
              [[ "$old_file" == "${manifestRelPath}" ]] && continue
              if [[ -f "$REPO_ROOT/$old_file" ]]; then
                echo "  Removing $old_file"
                rm "$REPO_ROOT/$old_file"
                rmdir "$(dirname "$REPO_ROOT/$old_file")" 2>/dev/null || true
              fi
            done < "$MANIFEST"
          fi

          ${lib.concatStrings fileSnippets}

          cp ${newManifestFile} "$MANIFEST"
          chmod u+w "$MANIFEST"
          echo "Done. Commit the changes and open a PR."
        '';
      };
    in
    {
      options.famedly.standards = {
        # Internal — modules register managed files here.
        _internal.managedFiles = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                src = lib.mkOption {
                  type = lib.types.path;
                  description = "Source file in the Nix store.";
                };
                dest = lib.mkOption {
                  type = lib.types.str;
                  description = "Destination path relative to the repo root.";
                };
              };
            }
          );
          default = [ ];
          internal = true;
          description = "Collected managed files from all standards modules.";
        };

        # Internal — dependabot ecosystem entries from flat options and projects.
        _internal.dependabotEntries = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                ecosystem = lib.mkOption {
                  type = lib.types.str;
                  description = "Dependabot package-ecosystem identifier.";
                };
                directory = lib.mkOption {
                  type = lib.types.str;
                  default = "/";
                  description = "Directory for this ecosystem (e.g. /backend).";
                };
                extraConfig = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Extra YAML lines to append to this entry.";
                };
              };
            }
          );
          default = [ ];
          internal = true;
          description = "Collected Dependabot entries from all modules.";
        };

        # Internal — pre-commit hook scopes from flat options and projects.
        _internal.hookEntries = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                scope = lib.mkOption {
                  type = lib.types.enum [
                    "rust"
                    "dart"
                    "python"
                  ];
                  description = "Language scope for this hook group.";
                };
                directory = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Subdirectory for this project (empty = repo root).";
                };
              };
            }
          );
          default = [ ];
          internal = true;
          description = "Collected pre-commit hook entries from all modules.";
        };
      };

      config = {
        apps.regenerateStandards = {
          type = "app";
          meta.description = "Write all engineering-standards managed files to the repo";
          program = lib.getExe regenerateScript;
        };
      };
    }
  );
}
