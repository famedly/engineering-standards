{ lib, flake-parts-lib, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }: {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.runtime = {
              libraries = lib.mkOption {
                description = ''
                  Packages whose libraries the project `dlopen`s by soname, such
                  as `sqlite` for `sqflite_common_ffi`.

                  A compiled Dart binary carries no `RUNPATH`, and the SDK is
                  patched to the nix loader, whose default search path covers
                  neither `/usr/lib` nor the nix store. So the libraries have to
                  be named, and they are needed wherever the project runs: they
                  land on the devshell's `LD_LIBRARY_PATH` and on the image's.
                '';
                type = lib.types.listOf lib.types.package;
                default = [ ];
                example = lib.literalExpression "[ pkgs.sqlite ]";
              };

              env = lib.mkOption {
                description = ''
                  Environment variables the project needs at runtime. Set in the
                  devshell and baked into the image.
                '';
                type = lib.types.attrsOf lib.types.str;
                default = { };
              };
            };
          }
        );
      };
    }
  );

  config.perSystem =
    { config, ... }:
    let
      projects = lib.attrValues config.famedly.standards.dart.projects;

      libraries = lib.concatMap (project: project.runtime.libraries) projects;

      # The devshell is per repository rather than per project, so a repository
      # with several projects gets the union of their environments.
      environment = lib.foldl' (all: project: all // project.runtime.env) { } projects;
    in
    lib.mkIf (projects != [ ]) {
      devshells.standards.env =
        lib.optional (libraries != [ ]) {
          name = "LD_LIBRARY_PATH";
          prefix = lib.makeLibraryPath libraries;
        }
        ++ lib.mapAttrsToList (name: value: { inherit name value; }) environment;
    };
}
