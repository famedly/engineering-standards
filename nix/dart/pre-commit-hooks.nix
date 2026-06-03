{
  flakeModules,
  inputs,
  flake-parts-lib,
  lib,
  ...
}:
importingFlake: {
  config.perSystem =
    {
      self',
      pkgs,
      config,
      ...
    }:
    let
      dart = lib.getExe' self'.packages.famedly-dart-toolchain "dart";
    in
    {
      prek-pre-commit.workspaces = lib.mapAttrs (name: _: {
        default_language_version.dart = "system";

        repos = [
          {
            repo = "local";
            hooks = [
              {
                id = "dart-analyze";
                name = "dart-analyze";
                description = "Run dart analyze on all targets";

                entry = "${dart} analyze --fatal-infos --fatal-warnings --fatal-lints";

                language = "system";
                types = [ "dart" ];
                pass_filenames = false;
              }
            ];
          }
        ];
      }) config.famedly.standards.dart.projects;
    };
}
