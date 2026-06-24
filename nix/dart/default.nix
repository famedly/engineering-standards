{
  flake-parts-lib,
  lib,
  importApply,
  ...
}@args:
importingFlake: {
  imports = [
    (importApply ./devshell.nix args)
    (importApply ./linting.nix args)
    (importApply ./sdk.nix args)
    ./workflow.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      description = ''
        Dart projects in the repository that should be equipped with our
        standards.

        The attribute key is the project's relative path, starting with `.`.
        Simply use `.` if the whole repository is a single Dart project.

        Setting this generates a `dart-ci` GitHub Actions workflow with a
        lint job per project (and optional test/coverage jobs).
      '';
      default = { };

      example = lib.literalExpression ''
        {
          "." = {
            sdk = "flutter";
            test = true;
            coverage = true;
          };
        }
      '';

      type = lib.types.attrsOf (
        lib.types.submodule (
          { ... }:
          {
            options = {
              sdk = lib.mkOption {
                type = lib.types.enum [
                  "flutter"
                  "dart"
                ];
                default = "flutter";
                description = "Which SDK the CI jobs install and run: `flutter` (default) or `dart`.";
              };

              importSorter = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Run `import_sorter` to check import ordering.";
              };

              dependencyValidator = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Run `dependency_validator` to check for unused dependencies.";
              };

              dartCodeLinter = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Run `dart_code_linter` for code metrics and unused code/files checks.";
              };

              translationsCleaner = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Run `translations_cleaner` to check for unused translations.";
              };

              commentedCodeCheck = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Check for commented-out Dart code.";
              };

              test = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Enable a test job (`dart test` / `flutter test`).";
              };

              coverage = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Enable a coverage job with Codecov upload.";
              };

              coverageFlags = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Flags to pass to Codecov (e.g. `sdk-tests`).";
              };

              testInDevShell = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Run the test/coverage commands inside `nix develop`. Enable this
                  when tests depend on native libraries (e.g. sqlite3 for
                  sqflite_common_ffi) that the Nix-installed SDK cannot find on its
                  own.
                '';
              };
            };
          }
        )
      );
    };
  });
}
