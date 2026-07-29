{ lib, flake-parts-lib, ... }:
importingFlake: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.linting.dartCodeLinter.enable = lib.mkEnableOption ''
            the `dart_code_linter` rule set for this project.

            Off by default, because these rules come from an analyzer plugin:
            the analysis server reports them in the editor, but `dart analyze`
            ignores them. Enabling them without also adding the
            `dart_code_linter` dev dependency and a
            `dart run dart_code_linter:metrics analyze` step therefore produces
            findings that CI never checks
          '';
        }
      );
    };
  });

  config.perSystem =
    { config, pkgs, ... }:
    let
      projects = config.famedly.standards.dart.projects;

      # Pinned here rather than only in the header below, so the version the
      # analyzer loads and the version we tell projects to depend on cannot
      # drift apart.
      riverpodLint = "^3.1.3";

      # Migrated from the `famedly_dart_lints` and `famedly_flutter_lints`
      # packages in famedly/frontend-ci-templates (`lints/dart` and
      # `lints/flutter`), which repositories used to pull in as a git
      # dependency.
      #
      # The two rule sets were kept in sync by hand there. Here the shared part
      # is shared, and only what is genuinely about widgets is conditional.
      rules = [
        "avoid_print"
        "constant_identifier_names"
        "prefer_final_locals"
        "prefer_final_in_for_each"
        "sort_pub_dependencies"
        "require_trailing_commas"
        "omit_local_variable_types"
        "cancel_subscriptions"
        "always_declare_return_types"
        "avoid_void_async"
        "no_adjacent_strings_in_list"
        "test_types_in_equals"
        "throw_in_finally"
        "unnecessary_statements"
        "avoid_bool_literals_in_conditional_expressions"
        "prefer_single_quotes"
        "prefer_const_declarations"
        "unnecessary_lambdas"
        "combinators_ordering"
        "noop_primitive_operations"
        "unnecessary_null_checks"
        "unnecessary_null_in_if_null_operators"
        "unnecessary_to_list_in_spreads"
        "use_is_even_rather_than_modulo"
        "use_super_parameters"
        "directives_ordering"
      ];

      flutterRules = [ "use_colored_box" ];

      dartCodeLinterRules = [
        "avoid-dynamic"
        "avoid-redundant-async"
        "avoid-unnecessary-type-assertions"
        "avoid-unnecessary-type-casts"
        "avoid-unrelated-type-assertions"
        "no-equal-then-else"
        "prefer-first"
        "prefer-last"
        "prefer-immediate-return"
        "prefer-enums-by-name"
        "avoid-unnecessary-conditionals"
        "prefer-match-file-name"
        "member-ordering"
        "avoid-global-state"
      ];

      # `late` is how widget state is usually initialized, so banning it is only
      # reasonable outside of Flutter.
      dartCodeLinterDartRules = [ "avoid-late-keyword" ];

      dartCodeLinterFlutterRules = [
        "prefer-media-query-direct-access"
        "avoid-wrapping-in-padding"
        "prefer-correct-edge-insets-constructor"
        "avoid-returning-widgets"
        { prefer-single-widget-per-file.ignore-private-widgets = true; }
        "prefer-extracting-callbacks"
      ];

      mkOptions =
        projectConfig:
        let
          inherit (projectConfig) flutter;
          dartCodeLinter = projectConfig.linting.dartCodeLinter.enable;
        in
        {
          # `flutter_lints` includes `lints/recommended.yaml` itself, so the
          # Flutter base is a superset of the Dart one.
          include =
            if flutter then "package:flutter_lints/flutter.yaml" else "package:lints/recommended.yaml";

          linter.rules = rules ++ lib.optionals flutter flutterRules;

          analyzer = {
            errors = {
              todo = "ignore";
              use_build_context_synchronously = "ignore";
            };

            exclude = [ "lib/l10n/*.dart" ];
          }
          // lib.optionalAttrs dartCodeLinter { plugins = [ "dart_code_linter" ]; };
        }
        // lib.optionalAttrs flutter {
          # Riverpod ships a modern analyzer plugin, which the analyzer resolves
          # from this top-level key rather than through `analyzer.plugins`.
          plugins.riverpod_lint = riverpodLint;
        }
        // lib.optionalAttrs dartCodeLinter {
          dart_code_linter.rules =
            dartCodeLinterRules ++ (if flutter then dartCodeLinterFlutterRules else dartCodeLinterDartRules);
        };

      # `builtins.readFile` on the generated file would force it at evaluation
      # time, so the header is prepended in a derivation instead.
      mkOptionsFile =
        projectConfig:
        let
          dependencies =
            (
              if projectConfig.flutter then
                [
                  "flutter_lints: ^6.0.0"
                  "riverpod_lint: ${riverpodLint}"
                ]
              else
                [ "lints: ^6.1.0" ]
            )
            ++ lib.optional projectConfig.linting.dartCodeLinter.enable "dart_code_linter: ^3.2.1";

          header = pkgs.writeText "analysis_options.standards.yaml.header" (
            ''
              # managed-by: engineering-standards — do not edit manually.
              #
              # Regenerate with `nix run .#filegen-activate`. Put repository-specific
              # overrides in `analysis_options.yaml`, which includes this file.
              #
              # Requires these dev dependencies:
              #
            ''
            + lib.concatLines (map (dependency: "#   ${dependency}") dependencies)
          );
        in
        pkgs.runCommand "analysis_options.standards.yaml" { } ''
          cat ${header} >$out
          cat ${(pkgs.formats.yaml { }).generate "analysis_options.yaml" (mkOptions projectConfig)} >>$out
        '';

      # Only the managed file is placed. The project's own
      # `analysis_options.yaml` has to include it — see the `dart-lints-included`
      # pre-commit hook, which is what keeps that from being forgotten.
      #
      # We deliberately don't place that file ourselves: `filegen` has no
      # "create once" mode — `clobber = false` still overwrites and merely
      # leaves a numbered backup behind — so we would trample the very
      # overrides it is meant to hold.
      inherit (import ../lib/project-paths.nix { inherit lib; }) directory;

      mkProjectFiles = project: projectConfig: [
        {
          type = "copy";
          target = "./${directory project}analysis_options.standards.yaml";
          source = mkOptionsFile projectConfig;
          clobber = true;
        }
      ];
    in
    lib.mkIf (projects != { }) {
      filegen.settings.files = lib.concatLists (lib.mapAttrsToList mkProjectFiles projects);
    };
}
