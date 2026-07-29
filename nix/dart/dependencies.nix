# `dependency_validator` holds a project's manifest against what its code
# actually imports: a dependency nobody imports, and an import nobody declared.
#
# The ignore list is generated, because the entries a project needs are mostly
# not its own doing. A linter is referenced from `analysis_options.yaml` rather
# than from Dart code, so the tool sees it declared and never used — and which
# linters a project declares is the standards' decision. Leaving that list to
# every repository means each one rediscovers it by reading a failing CI run.
{ lib, flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.checks.dependencies = {
              enable = lib.mkEnableOption "holding this project's declared dependencies against the ones it imports";

              ignore = lib.mkOption {
                description = ''
                  Packages to accept as declared but unimported, on top of the
                  linters the standards mandate.

                  For a package whose use the tool cannot see: an asset bundle,
                  or a plugin loaded by name at runtime.
                '';
                type = lib.types.listOf lib.types.str;
                default = [ ];
                example = [ "flutter_launcher_icons" ];
              };

              version = lib.mkOption {
                description = ''
                  Constraint the `dependency_validator` tool is installed under.

                  Installed globally rather than carried as a dev dependency,
                  since a tool that judges the manifest should not appear in it.
                '';
                type = lib.types.str;
                default = "^5.0.5";
              };
            };
          }
        );
      };
    }
  );

  config.perSystem =
    { config, pkgs, ... }:
    let
      inherit (import ../lib/project-paths.nix { inherit lib; }) directory;

      projects = lib.filterAttrs (
        _: project: project.checks.dependencies.enable
      ) config.famedly.standards.dart.projects;

      mkConfigFile =
        projectConfig:
        let
          # Kept beside the constraints in linting.nix: a linter that stops
          # being mandated has to stop being excused here in the same breath,
          # or the excuse outlives it.
          linters =
            if projectConfig.flutter then
              [
                "flutter_lints"
                "riverpod_lint"
              ]
            else
              [ "lints" ];

          # `dart_code_linter` is deliberately absent: it ships an executable,
          # which the tool takes as evidence enough of use.
          settings.ignore = lib.unique (linters ++ projectConfig.checks.dependencies.ignore);

          header = pkgs.writeText "dart_dependency_validator.yaml.header" ''
            # managed-by: engineering-standards — do not edit manually.
            #
            # Regenerate with `nix run .#filegen-activate`. Further entries belong in
            # the flake, under checks.dependencies.ignore.
          '';
        in
        pkgs.runCommand "dart_dependency_validator.yaml" { } ''
          cat ${header} >$out
          cat ${(pkgs.formats.yaml { }).generate "dart_dependency_validator.yaml" settings} >>$out
        '';
    in
    lib.mkIf (projects != { }) {
      filegen.settings.files = lib.mapAttrsToList (project: projectConfig: {
        type = "copy";
        target = "./${directory project}dart_dependency_validator.yaml";
        source = mkConfigFile projectConfig;
        clobber = true;
      }) projects;
    };
}
