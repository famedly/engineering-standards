# Main flake module for engineering-standards.
#
# Consumer repos import this module and configure it via:
#
#   perSystem = { ... }: {
#     famedly.standards = {
#       rules.enable = true;
#       linting.rust = true;
#       preCommitHooks.enable = true;
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
# Workflows are generated as complete YAML via github-actions-nix,
# eliminating the need for reusable workflow_call references.

{ flake-parts-lib, ... }:
let
  sdkVersions = import ../sdk-versions.nix;
in
{
  imports = [
    ./action-versions.nix
    ./compat.nix
    ./rules.nix
    ./linting.nix
    ./infrastructure.nix
    ./devshell.nix
    ./dart.nix
    ./projects.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      system,
      inputs',
      ...
    }:
    let
      cfg = config.famedly.standards;

      fileSnippets = map (
        entry:
        let
          destDir = builtins.dirOf entry.dest;
          writeCmd = ''
            mkdir -p "$REPO_ROOT/${destDir}"
            cp ${entry.src} "$REPO_ROOT/${entry.dest}"
            chmod u+w "$REPO_ROOT/${entry.dest}"
          '';
        in
        if entry.initialOnly then
          ''
            if [[ ! -f "$REPO_ROOT/${entry.dest}" ]]; then
              echo "  Creating ${entry.dest} (initial)"
              ${writeCmd}
            else
              echo "  Skipping ${entry.dest} (already exists, user-managed)"
            fi
          ''
        else
          ''
            echo "  Writing ${entry.dest}"
            ${writeCmd}
          ''
      ) cfg._internal.managedFiles;

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

          if [[ -f "$MANIFEST" ]]; then
            echo "Cleaning up files no longer managed..."
            while IFS= read -r old_file; do
              [[ -z "$old_file" ]] && continue
              [[ "$old_file" == "${manifestRelPath}" ]] && continue
              if ! grep -qxF "$old_file" ${newManifestFile}; then
                if [[ -f "$REPO_ROOT/$old_file" ]]; then
                  echo "  Removing $old_file"
                  rm "$REPO_ROOT/$old_file"
                  rmdir "$(dirname "$REPO_ROOT/$old_file")" 2>/dev/null || true
                fi
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
                initialOnly = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = ''
                    When true the file is only written on first run (if it does
                    not exist yet). Subsequent regenerations skip it so that
                    user customisations are preserved. The file is still tracked
                    in the manifest for cleanup when the feature is disabled.
                  '';
                };
              };
            }
          );
          default = [ ];
          internal = true;
          description = "Collected managed files from all standards modules.";
        };

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

      };

      config = {
        apps.regenerateStandards = {
          type = "app";
          meta.description = "Write all engineering-standards managed files to the repo";
          program = lib.getExe regenerateScript;
        };

        # SDK packages — same binaries used by DevShell and CI workflows.
        # famedly-dart-sdk: all 4 supported platforms.
        # famedly-flutter-sdk: not available on aarch64-linux (no upstream binary).
        # famedly-rust-toolchain: exposed when the flake has 'fenix' as an input
        #   (Rust template includes it). Stable Rust + nightly rustfmt + cargo-nextest.
        packages = {
          famedly-dart-sdk = pkgs.callPackage ../packages/dart-sdk.nix { inherit sdkVersions; };
        }
        // lib.optionalAttrs (lib.elem system [
          "x86_64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ]) { famedly-flutter-sdk = pkgs.callPackage ../packages/flutter-sdk.nix { inherit sdkVersions; }; }
        // lib.optionalAttrs (inputs' ? fenix) {
          famedly-rust-toolchain =
            let
              fenixPkgs = inputs'.fenix.packages;
            in
            pkgs.symlinkJoin {
              name = "famedly-rust-toolchain";
              paths = [
                (fenixPkgs.combine [
                  fenixPkgs.stable.cargo
                  fenixPkgs.stable.clippy
                  fenixPkgs.stable.rust-src
                  fenixPkgs.stable.rustc
                  fenixPkgs.stable.llvm-tools-preview
                  fenixPkgs.latest.rustfmt
                ])
                pkgs.cargo-nextest
                pkgs.cargo-llvm-cov
              ];
            };
        };
      };
    }
  );
}
