{ filegen, ... }:
{ flake-parts-lib, lib, ... }:
let
  inherit (lib) types;
in
{
  imports = [ filegen ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { pkgs, ... }:
    let
      settingsFormat = pkgs.formats.yaml { };
    in
    {
      options.prek-pre-commit = {
        package = lib.mkOption {
          description = "The `prek` package to use to execute pre-commit hooks";
          type = types.package;
          default = pkgs.prek;
        };

        workspaces = lib.mkOption {
          description = ''
            `prek` configuration for each workspace.

            See the [`prek` documentation](https://prek.j178.dev/workspace/) for details.
          '';
          default = { };
          type = types.attrsOf (types.submodule { freeformType = settingsFormat.type; });
        };
      };
    }
  );

  config.perSystem =
    { config, pkgs, ... }:
    let
      settingsFormat = pkgs.formats.yaml { };
    in
    {
      filegen.settings.files = lib.mapAttrsToList (workspace: config: {
        type = "copy";

        target = "${workspace}/.pre-commit-config.yaml";
        source = settingsFormat.generate "pre-commit-config.yaml" config;
        clobber = true;
      }) config.prek-pre-commit.workspaces;
    };
}
