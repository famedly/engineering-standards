{ lib, ... }:
importingFlake: {
  config.perSystem =
    { config, self', ... }:
    # The Dart SDK is a hefty download, so only pull it in for repositories
    # that actually contain Dart code.
    lib.mkIf (config.famedly.standards.dart.projects != { }) {
      treefmt = {
        programs.dart-format = {
          enable = true;
          package = self'.packages.famedly-dart-sdk;
        };

        # `treefmt.toml` is committed, so it must not contain store paths. The
        # SDK is on `PATH` via the devshell and the `prek` wrapper.
        settings.formatter.dart-format.command = "dart";
      };
    };
}
