## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, flake-parts-lib, ... }: {
  imports = [
    (import ./project-options.nix { inherit lib flake-parts-lib; } {
      options.runtime = {
        libraries = lib.mkOption {
          description = ''
            Packages whose libraries the project `dlopen`s by soname, such as
            `sqlite` for `sqflite_common_ffi`.

            A compiled Dart binary carries no `RUNPATH`, and the nix loader
            searches neither `/usr/lib` nor the store, so these have to be
            named. They land on the devshell's `LD_LIBRARY_PATH` and on the
            image's.
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
    })
  ];

  perSystem =
    { config, ... }:
    let
      projects = lib.attrValues config.famedly.standards.dart.projects;

      libraries = lib.concatMap (project: project.runtime.libraries) projects;

      # One devshell per repository, so the projects' environments are merged.
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
