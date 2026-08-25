## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  perSystem = { config, pkgs, ... }: {
    prek-pre-commit = {
      package.runtimePkgs = [ pkgs.reuse ];
      workspaces.".".repos = [
        {
          repo = "local";

          hooks = [
            {
              id = "reuse";
              name = "reuse";
              description = "Ensure compliance with REUSE recommendations";

              entry = "reuse";
              args = [ "lint-file" ];

              language = "system";
            }
          ];
        }
      ];

    };

    filegen.settings.files = pkgs.lib.mapAttrsToList (name: value: {
      type = "copy";
      target = ".github/workflows/${name}.yml.license";
      source = ../../flake.lock.license;
    }) config.githubActions.workflows;
  };
}
