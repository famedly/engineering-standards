# The devshell and the formatter both need a Dart SDK, and it has to be the same
# one: `dart format` output depends on the SDK version, so a formatter that
# differs from the `dart` on `PATH` would have the two rewrite each other's
# output. Naming the package in one place is what keeps them from drifting.
{ lib, flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart = {
      toolchain = lib.mkOption {
        description = ''
          The SDK that provides `dart` for this repository.

          Read this instead of naming an SDK package directly, so that everything
          which runs `dart` agrees on the version.
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
  });

  config.perSystem =
    {
      config,
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
      famedly.standards.dart = {
        inherit flutter;

        # The Flutter SDK ships its own `dart`, so a repository that holds any
        # Flutter project has to use it for its plain Dart projects too.
        # Shipping both would leave `dart` meaning whichever one happened to win
        # on `PATH`.
        toolchain =
          if flutter then
            self'.packages.famedly-flutter-sdk
              or (throw "A Flutter project is configured, but famedly-flutter-sdk is not packaged for ${system}. See nix/dart/sdk.nix in the engineering standards.")
          else
            self'.packages.famedly-dart-sdk;
      };
    };
}
