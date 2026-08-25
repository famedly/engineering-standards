## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# `dependency_validator` checks a project's manifest against what its code
# actually imports.
#
# We generate the ignore list, because most of what belongs on it isn't the
# project's doing. A linter is referenced from `analysis_options.yaml` rather
# than from Dart code, so the tool sees it declared and never used, and which
# linters a project declares is our decision.
{ lib, flake-parts-lib, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.checks.dependencies = {
            enable = lib.mkEnableOption "holding this project's declared dependencies against the ones it imports";

            ignore = lib.mkOption {
              description = ''
                Extra packages to accept as declared but unimported, on top of
                the linters we mandate. Use this for packages whose use the
                tool can't see, such as an asset bundle or a plugin that is
                loaded by name.
              '';
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "flutter_launcher_icons" ];
            };

            version = lib.mkOption {
              description = ''
                Version of the `dependency_validator` tool that CI installs.
                We install it globally, since a tool that judges the manifest
                shouldn't appear in it, and we state the version exactly
                because no lockfile holds it.
              '';
              type = lib.types.str;
              default = "5.0.5";
            };
          };
        }
      );
    };
  });

  config.perSystem =
    {
      config,
      pkgs,
      standardsLib,
      ...
    }:
    let
      inherit (standardsLib) directory;

      projects = lib.filterAttrs (
        _: project: project.checks.dependencies.enable
      ) config.famedly.standards.dart.projects;

      mkConfigFile =
        projectConfig:
        let
          # This mirrors linting.nix. A linter we stop mandating has to stop
          # being excused here too, or the excuse outlives it.
          linters =
            if projectConfig.flutter then
              [ "flutter_lints" ] ++ lib.optional projectConfig.linting.riverpodLint.enable "riverpod_lint"
            else
              [ "lints" ];

          # We leave out `dart_code_linter` on purpose, since it ships an
          # executable and the tool takes that as evidence enough of use.
          settings.ignore = lib.unique (linters ++ projectConfig.checks.dependencies.ignore);
        in
        standardsLib.managedFile {
          inherit pkgs;

          name = "dart_dependency_validator.yaml";
          file = (pkgs.formats.yaml { }).generate "dart_dependency_validator.yaml" settings;

          note = "Further entries belong in the flake, under `checks.dependencies.ignore`.";
        };
    in
    {
      filegen.settings.files = lib.mapAttrsToList (project: projectConfig: {
        type = "copy";
        target = "./${directory project}dart_dependency_validator.yaml";
        source = mkConfigFile projectConfig;
        clobber = true;
      }) projects;
    };
}
