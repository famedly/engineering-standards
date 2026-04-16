{
  lib,
  flake-parts-lib,
  moduleWithSystem,
  ...
}:
importingFlake: {
  config.perSystem = moduleWithSystem (
    { pkgs, ... }@_localFlake:
    { config, system, ... }@_importingFlake:

    let
      cfg = config.famedly.standards.preCommitHooks;
    in
    lib.mkIf cfg.reuseHook.enable {
      apps.addLicenseHeaders = {
        type = "app";
        meta.description = "Add SPDX license headers to all git-tracked files";
        program =
          (pkgs.writers.writeNu "add-license-headers" /* nu */ ''
            print 'Downloading missing license texts...'
            ${lib.getExe pkgs.reuse} download --all

            print 'Adding SPDX headers: --copyright=${cfg.fossHooks.copyright} --license=${cfg.fossHooks.license}'

            let tracked_files = ${lib.getExe pkgs.git} ls-files -z | split row (char --integer 0) | drop 1

            (${lib.getExe pkgs.reuse} annotate
              --copyright=${cfg.fossHooks.copyright}
              --license=${cfg.fossHooks.license}
              --skip-unrecognized
              ...$tracked_files)

            print "Done. Run 'reuse lint' to verify compliance."
          '').outPath;
      };

      famedly.standards._internal.managedFiles = [
        {
          src = pkgs.writers.writeTOML "REUSE.toml" (
            (lib.fromTOML ../../../linting/reuse/REUSE.toml)
            // {
              SPDX-FileCopyrightText = cfg.fossHooks.copyright;
              SPDX-License-Identifier = cfg.fossHooks.license;
            }
          );
          dest = "REUSE.toml";
          initialOnly = true;
        }
      ];

      pre-commit.settings.hooks.reuse.enable = true;
    }
  );
}
