# Nix options for workflow references and GitHub Action version pins.
#
# This module defines two options:
#   1. workflowRef — the git ref consumers use to reference our reusable
#      workflows (floating major tag like "v1"). Bump to "v2" for breaking changes.
#   2. actionVersions — commit-SHA pins for all third-party GitHub Actions,
#      read from nix/action-versions-data.nix (the actual source of truth).
#
# To update action version pins: edit nix/action-versions-data.nix, then run
#   nix run .#regenerateStandards
# in this repo. Consumer repos pick up the update via their flake.lock.

{ flake-parts-lib, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.workflowRef = lib.mkOption {
        type = lib.types.str;
        default = "v1";
        description = ''
          Git ref for engineering-standards reusable workflow references
          in generated caller workflows. Uses floating major tags (e.g. "v1")
          so that non-breaking fixes propagate automatically.

          Override temporarily for testing feature branches:
            famedly.standards.workflowRef = "my-feature-branch";
        '';
        example = "v2";
      };

      options.famedly.standards.actionVersions = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Canonical commit-SHA pins for all GitHub Actions used across workflows.";
      };

      config.famedly.standards.actionVersions = builtins.mapAttrs (_: entry: entry.sha) (
        import ../action-versions-data.nix
      );
    }
  );
}
