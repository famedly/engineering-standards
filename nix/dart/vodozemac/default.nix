{ lib, flake-parts-lib, ... }:
importingFlake: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { pkgs, ... }:
    let
      # The very package `packages.famedly-vodozemac` is built from, called
      # again rather than read off `self'`: reaching into the flake's own
      # packages from inside an option declaration would make the projects
      # depend on config that is derived from the projects.
      vodozemac = pkgs.callPackage ./native.nix { };
    in
    {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              options.vodozemac.enable = lib.mkEnableOption ''
                the native vodozemac bindings for this project.

                Points `flutter_rust_bridge`'s library lookup at the nix-built
                library, so `vod.init` finds it without the project having to
                check a copy into the repository or build one first. Needs no
                change to the Dart code: the loader prefers this over the
                `libraryPath` it was called with
              '';

              config.runtime.env = lib.mkIf config.vodozemac.enable {
                # `flutter_rust_bridge` runs this through `Uri.directory`, so it
                # must be a directory and takes no trailing slash. It appends
                # the platform-specific file name itself.
                FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR = "${vodozemac}/lib";
              };
            }
          )
        );
      };
    }
  );

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
        packages.famedly-vodozemac = pkgs.callPackage ./native.nix { };
        packages.famedly-vodozemac-web = pkgs.callPackage ./web.nix { };
      })

      # The lookup itself goes through `runtime.env`; this only makes entering
      # the shell build the library.
      (lib.mkIf needed { devshells.standards.packages = [ self'.packages.famedly-vodozemac ]; })
    ];
}
