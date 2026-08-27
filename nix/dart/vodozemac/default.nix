## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

{ lib, flake-parts-lib, ... }:
let
  # How the source and the native bindings are instantiated from the options,
  # shared between the option declaration and the flake's packages so that the
  # two cannot drift apart.
  mkSource = pkgs: cfg: pkgs.callPackage ./source.nix { inherit (cfg) version hash cargoHash; };
  mkBindings = pkgs: cfg: pkgs.callPackage ./native.nix { source = mkSource pkgs cfg; };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, ... }:
    let
      # What `packages.famedly-vodozemac` is built from. We call it again
      # instead of reading it off `self'`, since an option declaration that
      # reaches into the flake's packages makes the projects depend on
      # themselves.
      vodozemac = mkBindings pkgs config.famedly.standards.dart.vodozemac;
    in
    {
      options.famedly.standards.dart.vodozemac = {
        version = lib.mkOption {
          description = ''
            Which dart-vodozemac release to build the bindings from.

            Keep this equal to the `vodozemac` or `flutter_vodozemac`
            constraint in the project's `pubspec.yaml`, which a pre-commit
            hook checks. The Dart package is generated from this very release,
            and a mismatch fails at the first call rather than at build time.

            A project that can't follow the default yet sets its own, together
            with both hashes below.
          '';

          type = lib.types.str;
          default = "0.7.1";
        };

        hash = lib.mkOption {
          description = ''
            Hash of the release's source tree, which changes with `version`.
            Nix names the value it expected when this one disagrees.
          '';

          type = lib.types.str;
          default = "sha256-z1DCU9WH5XAf5QquV7loUOVM5OaZmLqziF4gR75/4rk=";
        };

        cargoHash = lib.mkOption {
          description = ''
            Hash of the crate's vendored dependencies, which changes with the
            release's `Cargo.lock`. Both targets share it, since which
            dependencies one links is decided when it is built and not when
            they are resolved.
          '';

          type = lib.types.str;
          default = "sha256-KsOyQyz9TqcmkHwuf3iA0NQU+pOOtoBVKv1AxZCjxnw=";
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

                This points `flutter_rust_bridge`'s library lookup at the
                nix-built library, so that `vod.init` finds it without the
                project having to check a copy into the repository or build
                one first. The Dart code needs no change, since the loader
                prefers this over the `libraryPath` it was called with.

                A project that also builds for the web gets the WebAssembly
                module placed in `web/pkg/`, where `vod.init` looks by
                default. An application that passes a `wasmPath` of its own
                has to drop it
              '';

              config.runtime.env = lib.mkIf config.vodozemac.enable {
                # `flutter_rust_bridge` runs this through `Uri.directory`, so
                # it has to be a directory and takes no trailing slash. It
                # appends the platform-specific file name itself.
                FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR = "${vodozemac}/lib";
              };
            }
          )
        );
      };
    }
  );

  config.perSystem =
    { config, pkgs, ... }:
    let
      cfg = config.famedly.standards.dart.vodozemac;
    in
    # The library needs no devshell entry of its own: `runtime.env`
    # interpolates its store path, so the shell already depends on it and
    # entering one builds it.
    lib.mkIf (config.famedly.standards.dart.projects != { }) {
      packages.famedly-vodozemac = mkBindings pkgs cfg;
      packages.famedly-vodozemac-web = pkgs.callPackage ./web.nix { source = mkSource pkgs cfg; };
    };
}
