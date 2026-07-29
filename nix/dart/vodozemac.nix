{ lib, flake-parts-lib, ... }:
importingFlake: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.vodozemac.enable = lib.mkEnableOption ''
            the native vodozemac bindings for this project.

            Points `flutter_rust_bridge`'s library lookup at the nix-built
            library, so `vod.init` finds it without the project having to
            check a copy into the repository or build one first. Needs no
            change to the Dart code: the loader prefers this over the
            `libraryPath` it was called with.
          '';
        }
      );
    };
  });

  config.perSystem =
    {
      config,
      pkgs,
      self',
      ...
    }:
    let
      needed = lib.any (project: project.vodozemac.enable) (
        lib.attrValues config.famedly.standards.dart.projects
      );
    in
    lib.mkMerge [
      (lib.mkIf (config.famedly.standards.dart.projects != { }) {
        packages.famedly-vodozemac = pkgs.callPackage ./packages/vodozemac.nix { };
      })

      (lib.mkIf needed {
        devshells.standards = {
          packages = [ self'.packages.famedly-vodozemac ];
          env = [
            {
              # `flutter_rust_bridge` runs this through `Uri.directory`, so it
              # must be a directory and takes no trailing slash. It appends the
              # platform-specific file name itself.
              name = "FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR";
              value = "${self'.packages.famedly-vodozemac}/lib";
            }
          ];
        };
      })
    ];
}
