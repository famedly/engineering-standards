## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, flake-parts-lib, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.runtime = {
            libraries = lib.mkOption {
              description = ''
                Packages whose libraries the project `dlopen`s by soname, for
                example `sqlite` for `sqflite_common_ffi`. A compiled Dart
                binary has no `RUNPATH`, so these have to be named here to end
                up on the `LD_LIBRARY_PATH` of the devshell and the image.
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
  });

  config.perSystem =
    { config, ... }:
    let
      projects = lib.attrValues config.famedly.standards.dart.projects;

      libraries = lib.concatMap (project: project.runtime.libraries) projects;

      # There is one devshell per repository, so we merge the projects'
      # environments together.
      environment = lib.mergeAttrsList (map (project: project.runtime.env) projects);
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
