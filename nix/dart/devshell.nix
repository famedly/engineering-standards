{ lib, ... }:
importingFlake: {
  config.perSystem =
    { config, ... }:
    let
      inherit (config.famedly.standards.dart) projects toolchain;
    in
    # The Dart SDK is a hefty download, so only pull it in for repositories
    # that actually contain Dart code.
    lib.mkIf (projects != { }) {
      devshells.standards = {
        packages = [ toolchain ];

        # `pub` resolves a `sdk: flutter` dependency — `flutter_test`, for one —
        # by reading this. The `dart` beside `flutter` in the SDK is the bare
        # binary, and nixpkgs wraps only `flutter`, so without this every `dart
        # pub` in a Flutter project stops at "the Flutter SDK is not available".
        # Flutter's own `bin/dart` script sets exactly this.
        env = lib.optional config.famedly.standards.dart.flutter {
          name = "FLUTTER_ROOT";
          value = "${toolchain}";
        };
      };
    };
}
