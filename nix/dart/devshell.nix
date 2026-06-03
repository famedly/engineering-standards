{ inputs, ... }:
importingFlake: {
  perSystem =
    {
      config,
      lib,
      self',
      pkgs,
      system,
      ...
    }:
    lib.mkMerge [
      {
        devshells.dart = {
          packages =
            (lib.attrValues {
              inherit (pkgs)
                dart
                ;
            })

            # TODO: Find a nice way to inherit all settings from the
            # general devshell, not just package.
            ++ config.devshells.general.packages;
        };

        # Install .envrc files that set up the correct devenv into all
        # Dart projects.
        filegen.settings.files = lib.mapAttrsToList (project: _: {
          type = "copy";
          target = "${project}/.envrc";
          source = pkgs.writeText ".envrc" ''
            use flake .#dart
          '';
          clobber = true;
        }) config.famedly.standards.dart.projects;
      }

      (lib.mkIf (lib.hasSuffix "linux" system) {
        devshells.dart.packages = lib.attrValues {
          inherit (pkgs)
            ;
        };
      })
    ];
}
