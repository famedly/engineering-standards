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
      prek-pre-commit.workspaces.".".repos = [
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
            {
              id = "mixed-line-ending";
              args = [ "--fix=lf" ];
            }
            { id = "check-symlinks"; }
            { id = "check-merge-conflict"; }
          ];
        }

        {
          repo = "local";
          hooks = [
            {
              id = "typos";
              name = "typos";
              description = "Check the repository for spelling mistakes";

              entry = lib.getExe pkgs.typos;
              args = [
                "--write-changes"
                "--force-exclude"
              ];

              language = "system";
              types = [ "text" ];
            }

            {
              id = "editorconfig";
              name = "editorconfig";
              description = "Ensure all files in the project match editorconfig rules";

              entry = lib.getExe pkgs.editorconfig-checker;
              language = "system";
            }
          ];
        }
      ];
    };
}
