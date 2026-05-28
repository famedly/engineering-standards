{
  flakeModules,
  inputs,
  lib,
  ...
}:
importingFlake: {
  config.perSystem =
    { pkgs, ... }:
    {
      prek-pre-commit.workspaces."." = {
        # Keep this up to date with the language list here:
        # https://prek.j178.dev/reference/configuration/#language
        default_language_version = lib.listToAttrs (
          map
            (name: {
              inherit name;
              value = "system";
            })
            [
              "python"
              "node"
              "rust"
              "golang"
              "ruby"
              "docker"
            ]
        );

        repos = [
          {
            repo = "builtin";

            # Regularly check this list for useful new lints, these
            # are generally pretty cheap since they're implemented in
            # rust and run in the same process:
            #
            # https://prek.j178.dev/builtin/#supported-hooks_1
            hooks = [
              { id = "trailing-whitespace"; }
              { id = "check-case-conflict"; }
              { id = "end-of-file-fixer"; }
              { id = "fix-byte-order-marker"; }
              { id = "check-json"; }
              { id = "check-toml"; }
              { id = "check-yaml"; }
              { id = "mixed-line-ending"; }
              { id = "check-symlinks"; }
              { id = "check-merge-conflict"; }
            ];
          }

          # TODO: Add these checks
          #
          # typos.enable = true;
          # ruff-check.enable = cfg.pythonHooks.enable;
          # ruff-format.enable = cfg.pythonHooks.enable;
        ];
      };
    };
}
