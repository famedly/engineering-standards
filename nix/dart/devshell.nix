{ lib, ... }:
importingFlake: {
  config.perSystem =
    { config, self', ... }:
    # The Dart SDK is a hefty download, so only pull it in for repositories
    # that actually contain Dart code.
    lib.mkIf (config.famedly.standards.dart.projects != { }) {
      devshells.standards.packages = [ self'.packages.famedly-dart-sdk ];
    };
}
