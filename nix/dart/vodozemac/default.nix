## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

{ lib, flake-parts-lib, ... }: importingFlake: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, ... }:
    let
      # The very package `packages.famedly-vodozemac` is built from, called
      # again rather than read off `self'`: reaching into the flake's own
      # packages from inside an option declaration would make the projects
      # depend on config that is derived from the projects.
      vodozemac = pkgs.callPackage ./native.nix {
        source = pkgs.callPackage ./source.nix {
          inherit (config.famedly.standards.dart.vodozemac) version hash cargoHash;
        };
      };
    in
    {
      options.famedly.standards.dart.vodozemac = {
        version = lib.mkOption {
          description = ''
            Which dart-vodozemac release to build the bindings from.

            Keep it equal to the `vodozemac` — or `flutter_vodozemac` —
            constraint in the project's `pubspec.yaml`. The Dart package that
            calls these bindings is generated from this very release, and a
            project talking to bindings it was not generated against fails when
            a call is made rather than when it is built, so a pre-commit hook
            compares the two.

            The default is the release we would like everyone on. A project that
            cannot follow yet sets its own, together with both hashes below,
            which is why they are options at all: nothing forces two projects
            onto one version of a dependency.
          '';

          type = lib.types.str;
          default = "0.5.0";
        };

        hash = lib.mkOption {
          description = ''
            Hash of the release's source tree, which changes with `version`.
            Nix names the value it expected when this one disagrees.
          '';

          type = lib.types.str;
          default = "sha256-H3g0is/+Cf3xBqqxw6qCjZSv5ZjftNSQP4hdwwEsOrs=";
        };

        cargoHash = lib.mkOption {
          description = ''
            Hash of the crate's vendored dependencies, which changes with the
            release's `Cargo.lock`. One lockfile, so one vendor: which
            dependencies a target links is decided when it is built, not when
            they are resolved, and both targets share this.
          '';

          type = lib.types.str;
          default = "sha256-eKKrcroV2yl/FV2WmgZWFPO5MPAGz0xCvpr0fgIuGZ4=";
        };
      };

      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }: {
              options.vodozemac.enable = lib.mkEnableOption ''
                the vodozemac bindings for this project. Which release they are
                built from is `famedly.standards.dart.vodozemac.version`, since
                the bindings are built once for the repository.

                Points `flutter_rust_bridge`'s library lookup at the nix-built
                library, so `vod.init` finds it without the project having to
                check a copy into the repository or build one first. Needs no
                change to the Dart code: the loader prefers this over the
                `libraryPath` it was called with.

                A project that also builds for the web gets the WebAssembly
                module placed in `web/pkg/`, where `vod.init` looks by default —
                an application that passes a `wasmPath` of its own has to drop
                it
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

      source = pkgs.callPackage ./source.nix {
        inherit (config.famedly.standards.dart.vodozemac) version hash cargoHash;
      };
    in
    lib.mkMerge [
      (lib.mkIf (config.famedly.standards.dart.projects != { }) {
        packages.famedly-vodozemac = pkgs.callPackage ./native.nix { inherit source; };
        packages.famedly-vodozemac-web = pkgs.callPackage ./web.nix { inherit source; };
      })

      # The lookup itself goes through `runtime.env`; this only makes entering
      # the shell build the library.
      (lib.mkIf needed { devshells.standards.packages = [ self'.packages.famedly-vodozemac ]; })
    ];
}
