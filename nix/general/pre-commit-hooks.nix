## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  flake-parts-lib,
  flakeModules,
  inputs,
  lib,
  ...
}:
importingFlake: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.detectPrivateKey.exclude = lib.mkOption {
      default = null;
      example = "^tests/(test\\.key|dummy-service-account\\.json)$";
      description = ''
        A regex of paths to exclude from the `detect-private-key` hook.

        Useful for repositories that deliberately commit dummy private keys
        as test fixtures. Prefer this over a workspace-wide `exclude`, which
        would also hide the matched files from every other hook (the
        json/toml checks, typos, reuse, …), not just `detect-private-key`.
      '';
      type = lib.types.nullOr lib.types.str;
    };
  });

  config.perSystem =
    {
      config,
      pkgs,
      self',
      ...
    }:
    {
      prek-pre-commit = {
        package.runtimePkgs = lib.attrValues (
          {
            inherit (pkgs) editorconfig-checker typos;
            treefmt = config.treefmt.package;
          }
          // config.treefmt.build.programs
        );

        workspaces.".".repos = [
          {
            repo = "builtin";

            # Regularly check this list for useful new lints, these
            # are generally pretty cheap since they're implemented in
            # rust and run in the same process:
            #
            # https://prek.j178.dev/builtin/#supported-hooks_1
            hooks = [
              # TODO: We want to use this, but it conflicts with rustfmt in places
              # In the future, we can simply make rustfmt run as a pre-commit hook
              # after trailing-whitespace, and it won't be a problem.
              # { id = "trailing-whitespace"; }
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

              # TODO: We would like to use this, but we need to tweak it
              # a little for helm charts.
              #
              # { id = "check-yaml"; }

              { id = "check-xml"; }
              {
                id = "mixed-line-ending";
                args = [ "--fix=lf" ];
              }
              { id = "check-symlinks"; }
              { id = "destroyed-symlinks"; }
              { id = "check-merge-conflict"; }
              {
                id = "detect-private-key";
                exclude = lib.mkIf (
                  config.famedly.standards.detectPrivateKey.exclude != null
                ) config.famedly.standards.detectPrivateKey.exclude;
              }

              # Branch protection rules should be set on the git forge
              # instead.
              #
              # { id = "no-commit-to-branch"; }

              {
                id = "check-shebang-scripts-are-executable";
                exclude_types = [
                  # Rust macros can look like shebangs
                  "rust"
                ];
              }
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

                entry = "typos";
                args = [
                  "--write-changes"
                  "--force-exclude"
                ];

                language = "system";
                types = [ "text" ];
              }

              # TODO: Currently too invasive for some downstreams, we
              # need to either tweak the configuration or make it
              # somewhat overridable.
              #
              # {
              #   id = "editorconfig";
              #   name = "editorconfig";
              #   description = "Ensure all files in the project match editorconfig rules";

              #   entry = "editorconfig-checker";
              #   language = "system";
              # }

              {
                id = "filegen";
                name = "filegen";
                description = "Ensure that files set up with the filegen module are up-to-date";
                pass_filenames = false;
                stages = [ "pre-push" ];

                entry = "nix run .#filegen-activate";
                language = "system";
              }

              {
                id = "treefmt";
                name = "treefmt";
                description = "Format *all* files";
                require_serial = true;

                entry = "treefmt";
                language = "system";
              }
            ];
          }
        ];
      };
    };
}
