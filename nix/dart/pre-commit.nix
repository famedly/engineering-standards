# Dart pre-commit hooks.
#
# When the repository has Dart projects, register a `dart format` hook in the
# root `prek` workspace and make the pinned Dart SDK available to the hook
# runner.
#
# Only `dart format` runs here: it is dependency-free and fast. The
# dependency-aware checks (analyze, import_sorter, dart_code_linter, …) need
# `pub get` and therefore live in the Dart CI workflow instead of prek.
{ ... }:
importingFlake: {
  perSystem =
    {
      config,
      lib,
      self',
      ...
    }:
    lib.mkIf (config.famedly.standards.dart.projects != { }) {
      prek-pre-commit = {
        package.runtimePkgs = [ self'.packages.famedly-dart-sdk ];

        workspaces.".".repos = [
          {
            repo = "local";
            hooks = [
              {
                id = "dart-format";
                name = "dart format";
                description = "Format Dart code with the pinned SDK";
                entry = "dart format";
                language = "system";
                types = [ "dart" ];
              }
            ];
          }
        ];
      };
    };
}
