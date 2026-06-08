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
            { id = "check-added-large-files"; }
            { id = "check-case-conflict"; }
            { id = "check-illegal-windows-names"; }
            { id = "end-of-file-fixer"; }

            # This needs very specific per-repo configuration, so we
            # don't globally enable it.
            #
            # {id = "file-contents-sorter";}

            { id = "fix-byte-order-marker"; }
            { id = "check-json"; }
            { id = "check-json5"; }

            # We should use treefmt-nix for this instead.
            #
            # { id = "pretty-format-json"; }

            { id = "check-toml"; }
            { id = "check-vcs-permalinks"; }
            { id = "check-yaml"; }
            { id = "check-xml"; }
            {
              id = "mixed-line-ending";
              args = [ "--fix=lf" ];
            }
            { id = "check-symlinks"; }
            { id = "destroyed-symlinks"; }
            { id = "check-merge-conflict"; }
            { id = "detect-private-key"; }

            # Branch protection rules should be set on the git forge
            # instead.
            #
            # { id = "no-commit-to-branch"; }

            { id = "check-shebang-scripts-are-executable"; }
            { id = "check-executables-have-shebangs"; }
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
