## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# `dependency_validator` holds a project's manifest against what its code
# actually imports.
#
# The ignore list is generated, because most of what belongs on it is not the
# project's doing: a linter is referenced from `analysis_options.yaml` rather
# than from Dart code, so the tool sees it declared and never used — and which
# linters a project declares is the standards' decision.
{ lib, flake-parts-lib, ... }: {
  imports = [
    (import ./project-options.nix { inherit lib flake-parts-lib; } {
      options.checks.dependencies = {
        enable = lib.mkEnableOption "holding this project's declared dependencies against the ones it imports";

        ignore = lib.mkOption {
          description = ''
            Packages to accept as declared but unimported, on top of the linters
            the standards mandate. For a package whose use the tool cannot see:
            an asset bundle, or a plugin loaded by name.
          '';
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "flutter_launcher_icons" ];
        };

        version = lib.mkOption {
          description = ''
            Version of the `dependency_validator` tool CI installs.

            Installed globally, since a tool that judges the manifest should not
            appear in it — which is also why the version is stated exactly: no
            lockfile holds it.
          '';
          type = lib.types.str;
          default = "5.0.5";
        };
      };
    })
  ];

  perSystem =
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
          # Mirrors linting.nix: a linter that stops being mandated has to stop
          # being excused here, or the excuse outlives it.
          linters =
            if projectConfig.flutter then
              [ "flutter_lints" ] ++ lib.optional projectConfig.linting.riverpodLint.enable "riverpod_lint"
            else
              [ "lints" ];

          # `dart_code_linter` is absent on purpose: it ships an executable,
          # which the tool takes as evidence enough of use.
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
