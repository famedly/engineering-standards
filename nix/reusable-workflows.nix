# Generates .github/workflows/ from templates in nix/workflow-sources/.
#
# Each template uses @tokenName@ placeholders that are replaced with
# "SHA # version" from action-versions-data.nix.
#
# Usage (in flake.nix):
#   workflows = import ./nix/reusable-workflows.nix { inherit pkgs lib; };
#   workflows.files  — attrset of { "filename.yml" = derivation; }
#   workflows.script — regenerateStandards helper (writes .github/workflows/)

{ pkgs, lib }:
let
  data = import ./action-versions-data.nix;
  templateDir = ./workflow-sources;

  keys = builtins.attrNames data;
  patterns = map (k: "@${k}@") keys;
  values = map (
    k:
    let
      e = data.${k};
    in
    "${e.sha} # ${e.v}"
  ) keys;

  substitute = content: builtins.replaceStrings patterns values content;

  templateFiles = builtins.attrNames (
    lib.filterAttrs (_: type: type == "regular") (builtins.readDir templateDir)
  );

  files = lib.listToAttrs (
    map (
      name:
      lib.nameValuePair name (
        pkgs.writeText name (substitute (builtins.readFile (templateDir + "/${name}")))
      )
    ) templateFiles
  );

  writeSnippets = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: src: ''
      echo "  Writing .github/workflows/${name}"
      cp ${src} "$REPO_ROOT/.github/workflows/${name}"
      chmod u+w "$REPO_ROOT/.github/workflows/${name}"
    '') files
  );

  regenerateScript = pkgs.writeShellApplication {
    name = "regenerateStandards";
    text = ''
      set -euo pipefail
      REPO_ROOT=$(git rev-parse --show-toplevel)
      echo "Regenerating .github/workflows/ (templates: nix/workflow-sources/, pins: nix/action-versions-data.nix)"
      mkdir -p "$REPO_ROOT/.github/workflows"
      ${writeSnippets}
      echo "Done. Review: git diff .github/workflows/"
    '';
  };
in
{
  inherit files;
  script = regenerateScript;
}
