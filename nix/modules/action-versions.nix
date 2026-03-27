# Canonical commit-SHA pins for all third-party GitHub Actions.
#
# Source of truth: nix/action-versions-data.nix
#
# Each entry maps a camelCase key to the pinned commit SHA.
# Workflow modules reference these via config.famedly.standards.actionVersions
# to pin action versions in generated workflow YAML.

{ flake-parts-lib, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
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
