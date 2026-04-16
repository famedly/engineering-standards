{
  lib,
  flake-parts-lib,
  moduleWithSystem,
  ...
}:
importingFlake: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.preCommitHooks.reuseHook.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable REUSE compliance hook.";
      };
    }
  );

  config.perSystem = moduleWithSystem (
    { pkgs, flake-parts-lib, ... }@_localFlake:
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
            # This script basically patches over a missing feature in
            # `reuse` that is being fixed upstream, see:
            #
            # https://codeberg.org/fsfe/reuse-tool/issues/1190
            #
            # As such, it should eventually be deprecated.
            let reuse = open REUSE.toml
            let copyright = $reuse.annotations.SPDX-FileCopyrightText.0
            let license = $reuse.annotations.SPDX-License-Identifier.0

            print 'Downloading missing license texts...'
            ${lib.getExe pkgs.reuse} download $license

            print $'Adding SPDX headers: --copyright=($copyright) --license=($license)'

            let tracked_files = ${lib.getExe pkgs.git} ls-files -z | split row (char --integer 0) | drop 1

            (${lib.getExe pkgs.reuse} annotate
              --copyright $copyright
              --license $license
              --skip-unrecognized
              ...$tracked_files)

            print "Done. Run 'reuse lint' to verify compliance."
          '').outPath;
      };

      famedly.standards._internal.managedFiles = [
        {
          src = ../../../linting/reuse/REUSE.toml;
          dest = "REUSE.toml";
          initialOnly = true;
        }
      ];

      pre-commit.settings.hooks.reuse.enable = true;
    }
  );
}
