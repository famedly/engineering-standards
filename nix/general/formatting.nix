## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  perSystem =
    {
      config,
      pkgs,
      standardsLib,
      ...
    }:
    {
      treefmt = {
        # `prek` is in charge of running these kinds of checks, we don't
        # want to run formatters with `nix flake check`.
        flakeCheck = false;

        settings = {
          allowMissingFormatter = false;
          walk = "git";

          excludes = config.filegen.generatedFiles;
        };

        # We include shfmt in general, because all projects probably use shell scripts
        programs.shfmt = {
          enable = true;
          # Setting the indent_size to 0 uses tabs for indentation
          indent_size = 0;
        };
        settings.formatter.shfmt.command = "shfmt";

        # taplo formats .toml files, which are virtually omnipresent
        programs.taplo = {
          enable = true;
          # We explicitly do not set `settings`, because it generates a nix
          # store path, and puts it in treefmt.toml
          # settings = builtins.fromTOML (builtins.readFile ./taplo.toml);
        };
        settings.formatter.taplo.command = "taplo";

      };

      filegen.settings.files = [
        {
          type = "copy";
          target = "treefmt.toml";
          source = standardsLib.managedFile {
            inherit pkgs;
            name = "treefmt.toml";
            file = config.treefmt.build.configFile;
          };
        }
        {
          type = "copy";
          target = ".taplo.toml";
          source = ./taplo.toml;
        }
      ];
    };
}
