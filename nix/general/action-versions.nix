{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.famedly.standards.allowed-action-versions = lib.mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, config, ... }:
        {
          options = {
            rev = lib.mkOption {
              description = ''
                The revision an action ref corresponds with at the time of review.

                This value is mostly kept for reference, and should not be used in
                `uses`, since the commits they refer to may be changed by upstream
                projects.
              '';
              type = types.str;
              readOnly = true;
            };

            ref = lib.mkOption {
              description = ''
                The permitted ref of the action; no other commits may be used.
              '';
              type = types.str;
              readOnly = true;
            };

            uses = lib.mkOption {
              description = ''
                The string for this action that should be used in GitHub workflow's
                `uses` options.
              '';
              type = types.str;
              readOnly = true;
            };
          };

          config.uses = "${name}@${config.ref}";
        }
      )
    );

    description = ''
      GitHub actions that are allowed to be used as dependencies in our actions.

      The key of each is a valid action name, and each has a `uses`
      attribute that can be used in a flows' `uses` settings.

      E.g.:

      ```nix
      { config, ... }:
      let
        allowed-actions = config.famedly.standards.allowed-action-versions;
      in
      {
        perSystem.githubActions.workflows.foo = {
          name = "Foo workflow";
          jobs.bar.steps = [
            {
              uses = allowed-actions."actions/checkout".uses;
            }
          ];
        };
      }
      ```
    '';
    readOnly = true;
  };

  config.famedly.standards.allowed-action-versions = builtins.fromTOML (
    builtins.readFile ../../standards/allowed-github-actions.toml
  );
}
