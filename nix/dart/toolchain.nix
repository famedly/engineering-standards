## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The devshell and the formatter have to use the same Dart SDK, since the
# output of `dart format` depends on the SDK version and two of them would
# keep rewriting each other's output.
{ lib, flake-parts-lib, ... }:
let
  # Upstream only publishes Flutter's prebuilt engine artifacts for some of
  # our platforms. We leave out the ones where they don't exist, so that the
  # toolchain can say so instead of failing in a fetch.
  flutterSystems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.famedly.standards.dart = {
      toolchain = lib.mkOption {
        description = ''
          The SDK that provides `dart` for this repository. Read this instead
          of naming a package, so that everything which runs `dart` agrees on
          the version.
        '';
        type = lib.types.package;
        readOnly = true;
      };

      flutter = lib.mkOption {
        description = ''
          Whether any project in the repository is a Flutter project, which
          means the toolchain above is the Flutter SDK.
        '';
        type = lib.types.bool;
        readOnly = true;
      };
    };
  };

  config.perSystem =
    {
      config,
      pkgs,
      self',
      system,
      ...
    }:
    let
      flutter = lib.any (project: project.flutter) (
        lib.attrValues config.famedly.standards.dart.projects
      );
    in
    {
      packages = {
        famedly-dart-sdk = pkgs.callPackage ./packages/dart-sdk.nix { };
      }
      // lib.optionalAttrs (lib.elem system flutterSystems) {
        famedly-flutter-sdk = pkgs.callPackage ./packages/flutter-sdk.nix { };
      };

      famedly.standards.dart = {
        inherit flutter;

        # The Flutter SDK ships its own `dart`, so we use it for the plain
        # Dart projects too. Shipping both would leave `dart` meaning
        # whichever one won on `PATH`.
        toolchain =
          if flutter then
            self'.packages.famedly-flutter-sdk
              or (throw "A Flutter project is configured, but famedly-flutter-sdk is not packaged for ${system}. See nix/dart/toolchain.nix in the engineering standards.")
          else
            self'.packages.famedly-dart-sdk;
      };
    };
}
