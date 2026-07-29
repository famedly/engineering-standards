# The devshell and the formatter both need a Dart SDK, and it has to be the same
# one: `dart format` output depends on the SDK version, so a formatter that
# differs from the `dart` on `PATH` would have the two rewrite each other's
# output. Naming the package in one place is what keeps them from drifting.
{ lib, flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.toolchain = lib.mkOption {
      description = ''
        The SDK that provides `dart` for this repository.

        Read this instead of naming an SDK package directly, so that everything
        which runs `dart` agrees on the version.
      '';
      type = lib.types.package;
      readOnly = true;
    };
  });

  config.perSystem =
    { self', ... }:
    {
      famedly.standards.dart.toolchain = self'.packages.famedly-dart-sdk;
    };
}
