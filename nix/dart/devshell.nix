{ ... }:
importingFlake: {
  perSystem =
    {
      config,
      lib,
      self',
      ...
    }:
    {
      devshells.dart = {
        # Ship the same pinned SDK that CI uses, so local and CI builds
        # match.
        #
        # Where Flutter is available we prefer it: the Flutter SDK bundles a
        # full Dart SDK, so a single package covers both `flutter` and `dart`
        # projects without colliding `dart` binaries. On platforms without an
        # upstream Flutter binary (aarch64-linux) we fall back to the
        # standalone Dart SDK.
        packages = [
          (self'.packages.famedly-flutter-sdk or self'.packages.famedly-dart-sdk)
        ];

        # TODO: Find a better way to inherit devshell
        # configurations.
        commands = lib.filter (command: command.name != "menu") config.devshells.standards.commands;
      };
    };
}
