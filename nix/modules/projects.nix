# Projects module: defines sub-projects in a monorepo.
#
# Each project has a language and a directory. The module automatically
# configures linting files, Dependabot entries, and pre-commit hooks
# scoped to that directory.
#
# Usage:
#   famedly.standards.projects = {
#     backend  = { language = "rust";    directory = "backend"; };
#     frontend = { language = "flutter"; directory = "frontend"; };
#   };
#
# A project with directory = "" places files at the repo root (equivalent
# to using the flat linting/hooks options directly).

{ flake-parts-lib, lib, ... }:
let
  root = ../..;
  lintingDir = "${root}/linting";

  languageToLintingScope = lang: if lang == "flutter" then "flutter" else lang;

  languageToDependabotEcosystem = {
    rust = "cargo";
    dart = "pub";
    flutter = "pub";
    python = "pip";
    typescript = "npm";
  };

  languageToHookScope = {
    rust = "rust";
    dart = "dart";
    flutter = "dart";
    python = "python";
    typescript = null;
  };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards;
      projects = cfg.projects;
      projectList = lib.attrsToList projects;

      # Collect linting files for a single project, prefixed with its directory.
      lintingFilesForProject =
        project:
        let
          scope = languageToLintingScope project.value.language;
          dir = "${lintingDir}/${scope}";
          prefix = if project.value.directory == "" then "" else "${project.value.directory}/";
        in
        if project.value.linting && builtins.pathExists dir then
          lib.mapAttrsToList (fname: _: {
            src = "${dir}/${fname}";
            dest = "${prefix}${fname}";
          }) (builtins.readDir dir)
        else
          [ ];

      allLintingFiles = lib.concatMap lintingFilesForProject projectList;

      # Collect Dependabot entries for all projects.
      dependabotEntries = lib.concatMap (
        project:
        let
          eco = languageToDependabotEcosystem.${project.value.language} or null;
          dir = if project.value.directory == "" then "/" else "/${project.value.directory}";
        in
        if project.value.dependabot && eco != null then
          [
            {
              ecosystem = eco;
              directory = dir;
            }
          ]
        else
          [ ]
      ) projectList;

      # Collect hook entries for all projects.
      hookEntries = lib.concatMap (
        project:
        let
          scope = languageToHookScope.${project.value.language} or null;
        in
        if project.value.hooks && scope != null then
          [
            {
              inherit scope;
              directory = project.value.directory;
            }
          ]
        else
          [ ]
      ) projectList;
    in
    {
      options.famedly.standards.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              language = lib.mkOption {
                type = lib.types.enum [
                  "rust"
                  "dart"
                  "flutter"
                  "python"
                  "typescript"
                ];
                description = "Primary language of this sub-project.";
              };

              directory = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = ''
                  Directory relative to the repo root.
                  Empty string means the project lives at the root.
                '';
                example = "backend";
              };

              linting = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Sync linting configuration files for this project.";
              };

              dependabot = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Include this project's ecosystem in Dependabot.";
              };

              hooks = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Include pre-commit hooks for this project's language.";
              };
            };
          }
        );
        default = { };
        description = ''
          Sub-projects in a monorepo. Each project gets linting configs in
          its directory, a Dependabot entry, and scoped pre-commit hooks.
        '';
        example = {
          backend = {
            language = "rust";
            directory = "backend";
          };
          frontend = {
            language = "flutter";
            directory = "frontend";
          };
        };
      };

      config = lib.mkIf (projects != { }) {
        famedly.standards._internal.managedFiles = allLintingFiles;
        famedly.standards._internal.dependabotEntries = dependabotEntries;
        famedly.standards._internal.hookEntries = hookEntries;
      };
    }
  );
}
