# Dart linting configuration.
#
# For every configured Dart project, place the shared analyzer configuration
# via filegen:
#
#   analysis_options.standards.yaml  — managed, always overwritten
#   analysis_options.yaml            — created once, then owned by the repo
#
# The standards file drives `dart analyze`, the IDE analyzer, and the
# `dart_code_linter` step of the Dart CI workflow, so local and CI analysis
# share one source of truth.
{ ... }:
importingFlake: {
  perSystem =
    { config, lib, ... }:
    let
      projects = config.famedly.standards.dart.projects;

      mkProjectFiles =
        name: _:
        let
          dir = if name == "." then "" else "${lib.removePrefix "./" name}/";
        in
        [
          {
            type = "copy";
            target = "./${dir}analysis_options.standards.yaml";
            source = ../../standards/dart/analysis_options.standards.yaml;
            clobber = true;
          }
          {
            type = "copy";
            target = "./${dir}analysis_options.yaml";
            source = ../../standards/dart/analysis_options.yaml;
            clobber = false;
          }
        ];
    in
    lib.mkIf (projects != { }) {
      filegen.settings.files = lib.concatLists (lib.mapAttrsToList mkProjectFiles projects);
    };
}
