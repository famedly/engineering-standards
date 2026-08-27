## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, flake-parts-lib, ... }:
let
  # Kept next to each other, since which linters we mandate and which versions
  # of them we generate configuration for is one decision.
  constraints = {
    lints = "^6.1.0";
    flutter_lints = "^6.0.0";
    riverpod_lint = "^3.1.3";
    dart_code_linter = "^4.1.2";
  };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }: {
            options.linting.exclude = lib.mkOption {
              description = ''
                Extra paths the analyzer should not look at, on top of the
                generated localisations. Use this for generated code, where a
                finding isn't something anybody can act on.
              '';

              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "lib/shared/l10n/*.dart" ];
            };

            options.linting.dartCodeLinter = {
              enable = lib.mkEnableOption ''
                the `dart_code_linter` rule set for this project.

                These rules come from an analyzer plugin that `dart analyze`
                ignores, so they need a separate step, which the checks workflow
                adds when this is enabled. The project has to carry the
                `dart_code_linter` dev dependency for that step to resolve
              '';

              extraRules = lib.mkOption {
                description = ''
                  Extra rules for this project, on top of the standard set. A
                  rule that takes configuration is a one-entry attribute set.

                  These belong here and not in the project's own
                  `analysis_options.yaml`, since the analyzer replaces the rule
                  list of an included file instead of merging it, and rules
                  spelled out there would silently drop ours.
                '';

                type = lib.types.listOf (lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything));
                default = [ ];

                example = lib.literalExpression ''
                  [
                    {
                      avoid-banned-imports.entries = [
                        {
                          paths = [ "features/.*\\.dart" ];
                          deny = [ "services/implementations.*\\.dart" ];
                          message = "Use the service API instead.";
                        }
                      ];
                    }
                  ]
                '';
              };

              disabledRules = lib.mkOption {
                description = ''
                  Standard rules this project doesn't follow yet. We keep them in
                  one place instead of as overrides that read like decisions.
                '';

                type = lib.types.listOf lib.types.str;
                default = [ ];
                example = [ "member-ordering" ];
              };
            };

            options.linting.riverpodLint.enable = lib.mkOption {
              description = ''
                Whether to load the `riverpod_lint` analyzer plugin for a Flutter
                project.

                We expect every Flutter project to reach Riverpod 3 eventually,
                so this is on by default. Turn it off for a project that hasn't,
                since the plugin's current release requires it and a plugin that
                can't resolve fails every analysis.
              '';
              type = lib.types.bool;
              default = true;
            };

            options.linting.packages = lib.mkOption {
              description = ''
                The dev dependencies the generated lint configuration needs, as
                version constraints keyed by package.

                Derived, because three things have to agree on it and used to
                each carry their own copy: the note that tells the project what
                to depend on, the `dependency_validator` ignore list, and the
                hook that holds the project's manifest against this.
              '';

              readOnly = true;

              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    constraint = lib.mkOption {
                      description = "Version constraint the project has to declare.";
                      type = lib.types.str;
                    };

                    excused = lib.mkOption {
                      description = ''
                        Whether `dependency_validator` has to be told this
                        package is used.

                        A linter is referenced from `analysis_options.yaml`
                        rather than from Dart code, so the tool sees it declared
                        and never imported — unless it ships an executable,
                        which the tool takes as evidence enough.
                      '';
                      type = lib.types.bool;
                      default = true;
                    };
                  };
                }
              );
            };

            config.linting.packages =
              (
                if config.flutter then
                  {
                    flutter_lints.constraint = constraints.flutter_lints;
                  }
                  // lib.optionalAttrs config.linting.riverpodLint.enable {
                    riverpod_lint.constraint = constraints.riverpod_lint;
                  }
                else
                  { lints.constraint = constraints.lints; }
              )
              // lib.optionalAttrs config.linting.dartCodeLinter.enable {
                dart_code_linter = {
                  constraint = constraints.dart_code_linter;
                  excused = false;
                };
              };
          }
        )
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
      inherit (config.famedly.standards.dart) projects;

      # Taken from `famedly_dart_lints` and `famedly_flutter_lints` in
      # famedly/frontend-ci-templates, which kept the two sets in sync by hand.
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

      # Only for plain Dart, since `late` is how widget state is usually
      # initialized.
      dartCodeLinterDartRules = [ "avoid-late-keyword" ];

      dartCodeLinterFlutterRules = [
        "prefer-media-query-direct-access"
        "avoid-wrapping-in-padding"
        "prefer-correct-edge-insets-constructor"
        "avoid-returning-widgets"
        { prefer-single-widget-per-file.ignore-private-widgets = true; }
        "prefer-extracting-callbacks"
      ];

      ruleName = rule: if lib.isString rule then rule else lib.head (lib.attrNames rule);

      mkOptions =
        projectConfig:
        let
          inherit (projectConfig) flutter;
          cfg = projectConfig.linting.dartCodeLinter;

          # The standard set for this kind of project, minus the rules it
          # doesn't follow yet, plus its own.
          pluginRules =
            let
              standard =
                dartCodeLinterRules ++ (if flutter then dartCodeLinterFlutterRules else dartCodeLinterDartRules);

              stale = lib.subtractLists (map ruleName standard) cfg.disabledRules;
            in
            assert lib.assertMsg (stale == [ ]) ''
              famedly.standards.dart.projects: disabledRules names ${lib.concatStringsSep ", " stale}, which the standard rule set does not contain.
            '';
            # We remove a disabled rule instead of restating it as
            # `rule: false`, which would list it twice and leave the outcome
            # to reading order.
            lib.filter (rule: !lib.elem (ruleName rule) cfg.disabledRules) standard ++ cfg.extraRules;
        in
        {
          # `flutter_lints` includes `lints/recommended.yaml` itself.
          include =
            if flutter then "package:flutter_lints/flutter.yaml" else "package:lints/recommended.yaml";

          linter.rules = rules ++ lib.optionals flutter flutterRules;

          analyzer = {
            errors = {
              todo = "ignore";
              use_build_context_synchronously = "ignore";
            };

            exclude = [ "lib/l10n/*.dart" ] ++ projectConfig.linting.exclude;
          }
          // lib.optionalAttrs cfg.enable { plugins = [ "dart_code_linter" ]; };
        }
        // lib.optionalAttrs (flutter && projectConfig.linting.riverpodLint.enable) {
          # A modern plugin, so it is resolved here rather than through
          # `analyzer.plugins`. Read from the same place the project is told
          # to depend on, so the analyzer can't load a version the manifest
          # doesn't allow.
          plugins.riverpod_lint = projectConfig.linting.packages.riverpod_lint.constraint;
        }
        // lib.optionalAttrs cfg.enable { dart_code_linter.rules = pluginRules; };

      mkOptionsFile =
        projectConfig:
        let
          dependencies = lib.mapAttrsToList (
            package: settings: "${package}: ${settings.constraint}"
          ) projectConfig.linting.packages;
        in
        standardsLib.managedFile {
          inherit pkgs;

          name = "analysis_options.standards.yaml";
          file = (pkgs.formats.yaml { }).generate "analysis_options.yaml" (mkOptions projectConfig);

          note = ''
            Put repository-specific overrides in `analysis_options.yaml`, which
            includes this file.

            Requires these dev dependencies:

            ${lib.concatStringsSep "\n" (map (dependency: "  ${dependency}") dependencies)}
          '';
        };

      # We only write the managed file. The project's own
      # `analysis_options.yaml` has to include it, which the
      # `dart-lints-included` hook checks. Writing that one ourselves would
      # trample the overrides it is meant to hold, since `filegen` has no
      # create-once mode.
      mkProjectFiles = project: projectConfig: [
        {
          type = "copy";
          target = "${project}/analysis_options.standards.yaml";
          source = mkOptionsFile projectConfig;
          clobber = true;
        }
      ];
    in
    {
      filegen.settings.files = lib.concatLists (lib.mapAttrsToList mkProjectFiles projects);
    };
}
