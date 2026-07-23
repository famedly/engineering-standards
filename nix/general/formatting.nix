{
  perSystem =
    { config, ... }:
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

      };

      filegen.settings.files = [
        {
          type = "copy";
          target = "treefmt.toml";
          source = config.treefmt.build.configFile;
        }
      ];
    };
}
