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

        # prettier formats JSON, YAML, Markdown, JS/TS, CSS, HTML, …
        programs.prettier.enable = true;
        # We explicitly do not set `settings`, because it generates a nix
        # store path, and puts it in treefmt.toml
        # Instead, we generate a `.prettierrc.yaml` with filegen further down.
        settings.formatter.prettier = {
          command = "prettier";
          # Helm templates match `*.yaml` but are Go templates. Formatting them
          # as YAML corrupts them.
          excludes = [
            "**/charts/**/templates/*.yaml"
            "**/charts/**/templates/*.yml"
            "**/charts/**/templates/**/*.yaml"
            "**/charts/**/templates/**/*.yml"
          ];
        };

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
        {
          type = "copy";
          target = ".prettierrc.yaml";
          source = ../../standards/prettierrc.yaml;
        }
      ];
    };
}
