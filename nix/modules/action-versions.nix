# Canonical version pins — update here, propagates everywhere.
#
# This module is the single source of truth for:
#   1. workflowRef — the git ref consumers use to reference our reusable
#      workflows (floating major tag like "v1"). Bump to "v2" for breaking changes.
#   2. actionVersions — commit-SHA pins for all third-party GitHub Actions.
#
# To update: bump versions here, then run
#   nix run .#regenerateStandards
# in every consumer repo (or let the auto-update workflow do it).

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
