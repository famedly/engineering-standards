{
  config.perSystem =
    { config, pkgs, ... }:
    {
      prek-pre-commit = {
        package.runtimePkgs = [ pkgs.flake-edit ];

        # All projects have at least a `flake.nix`, so some hooks
        # should run on all projects
        workspaces.".".repos = [
          {
            repo = "local";

            hooks = [
              {
                id = "flake-follows";
                name = "flake-follows";
                description = "Ensure that flake inputs are recursively de-duplicated";

                entry = "flake-edit";
                args = [ "follow" ];
                pass_filenames = false;

                language = "system";
                files.glob = "{flake.nix,flake.lock}";
              }
            ];
          }
        ];
      };
    };
}
