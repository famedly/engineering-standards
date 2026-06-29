{ lib, ... }:
importingFlake: {
  config.perSystem =
    { pkgs, config, ... }:
    lib.mkIf (config.famedly.standards.dart.projects != { }) {
      prek-pre-commit = {
        # Make dart available to the hook runner at runtime.
        package.runtimePkgs = [ pkgs.dart ];

        # Add dart-format to the root workspace's repos list.
        # This concatenates with the builtin/general hooks already defined
        # in nix/general/pre-commit-hooks.nix.
        workspaces.".".repos = [
          {
            repo = "local";
            hooks = [
              {
                id = "dart-pub-get";
                name = "dart pub get";
                description = "Fetch Dart dependencies before formatting";
                entry = "dart pub get --no-example";
                language = "system";
                pass_filenames = false;
                always_run = true;
              }
              {
                id = "dart-format";
                name = "dart format";
                description = "Format Dart source code";
                entry = "dart format .";
                language = "system";
                pass_filenames = false;
                types = [ "file" ];
                files = "\\.dart$";
              }
            ];
          }
        ];
      };
    };
}
