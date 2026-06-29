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
                id = "dart-format";
                name = "dart format";
                description = "Format Dart source code";
                entry = "dart format";
                language = "system";
                types = [ "file" ];
                files = "\\.dart$";
              }
            ];
          }
        ];
      };
    };
}
