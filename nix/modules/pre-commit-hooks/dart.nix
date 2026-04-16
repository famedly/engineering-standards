{
  lib,
  flake-parts-lib,
  moduleWithSystem,
  ...
}:
importingFlake: {
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.famedly.standards.preCommitHooks.dartHooks.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Dart hooks (dart format, dart analyze, import_sorter, commented-out code) at the repo root.";
    };
  };

  config.perSystem = moduleWithSystem (
    { self', pkgs }:
    { config, ... }:
    let
      inherit (config.pre-commit.settings) tools;

      cfg = config.famedly.standards.preCommitHooks;
      dartBin = lib.getExe' "dart" tools.dart;
    in
    lib.mkIf cfg.dartHooks.enable {
      pre-commit.settings = {
        tools.dart = self'.famedly-dart-sdk;

        hooks = {
          dart-format.enable = true;

          dart-analyze = {
            enable = true;

            # TODO: Ensure this is actually necessary; it seems that
            # with dart 2.13 onwards, per-file analysis is supported,
            # but maybe this misses library-level issues?
            pass_filenames = false;
          };

          dart-import-sorter = {
            enable = true;
            name = "import_sorter";
            # TODO: Similar to dart-code-linter, if we want to support
            # repositories that don't use the import_sorter, we may
            # need to parse pubspec.yaml?
            #
            # Or maybe the LLM just invented that need.
            entry = "${dartBin} run import_sorter:main --no-comments --exit-if-changed";
            language = "system";
            types = [ "dart" ];
          };

          # TODO: This doesn't seem dart-specific, nor does it really
          # seem like a useful linter, do we actually want this, or
          # should we make it more generic?
          dart-commented-code = {
            enable = true;
            name = "commented-out Dart code";
            entry = "${lib.getExe pkgs.grep} --line-number '^[[:space:]]*//[^/<].*;[[:space:]]*$'";
            language = "system";
            types = [ "dart" ];
          };

          dart-code-linter = {
            enable = true;
            name = "dart_code_linter analyze";

            entry = pkgs.writeNu "dart_code_linter" /* nu */ ''
              let code_roots = ["lib/" "bin/"] | where ($it | path exists)

              if ($code_roots | is-empty) or ("dart_code_linter" in (open pubspec.yaml).analyzer.plugins) {
                exit
              }

              ${dartBin} run dart_code_linter:metrics analyze ...$dirs --set-exit-on-violation-level=noted
            '';
            language = "system";
            types = [ "dart" ];

            # TODO: Similar to dart-analyze.pass_filenames, maybe we
            # can just run this linter on every file individually?
            pass_filenames = false;
          };
        };
      };
    }
  );
}
