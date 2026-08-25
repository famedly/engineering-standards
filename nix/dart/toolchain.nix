## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The devshell and the formatter need the same Dart SDK: `dart format` output
# depends on the version, so two of them would rewrite each other's output.
{ lib, flake-parts-lib, ... }:
let
  # Upstream publishes Flutter's prebuilt engine artifacts for some of our
  # platforms and not others. Left out where they do not exist, so the
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
          The SDK that provides `dart` for this repository. Read this rather
          than naming a package, so everything that runs `dart` agrees on the
          version.
        '';
        type = lib.types.package;
        readOnly = true;
      };

      flutter = lib.mkOption {
        description = ''
          Whether any project here is a Flutter one, and the toolchain above is
          therefore the Flutter SDK.
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

        # The Flutter SDK ships its own `dart`, so a repository with any
        # Flutter project uses it for the plain Dart ones too — shipping both
        # would leave `dart` meaning whichever won on `PATH`.
        toolchain =
          if flutter then
            self'.packages.famedly-flutter-sdk
              or (throw "A Flutter project is configured, but famedly-flutter-sdk is not packaged for ${system}. See nix/dart/toolchain.nix in the engineering standards.")
          else
            self'.packages.famedly-dart-sdk;
      };
    };
}
