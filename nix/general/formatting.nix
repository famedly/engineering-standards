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

        programs = {
          prettier.enable = true;
          sqlfluff.enable = true;
          shfmt.enable = true;
        };

        settings.formatter.prettier.excludes = [ "*.md" ];
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
