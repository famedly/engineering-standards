# Linting module: syncs language-specific linting configurations.
#
# Source files live in engineering-standards under linting/<scope>/.
# Generated files in consumer repo depend on detected language:
#
#   Dart/Flutter:
#     analysis_options.standards.yaml  (managed — always overwritten)
#     analysis_options.yaml            (initialOnly — created once, user-editable)
#   Rust:   clippy.toml, rustfmt.toml, deny.toml, cargo-lints.toml
#   Python: ruff.toml, ruff.base.toml

{ flake-parts-lib, ... }:
let
  root = ../..;
  lintingDir = "${root}/linting";

  # Files named analysis_options.yaml are user-editable (initialOnly);
  # analysis_options.standards.yaml and everything else is always managed.
  isInitialOnly = name: name == "analysis_options.yaml";
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, lib, ... }:
    let
      cfg = config.famedly.standards.linting;

      filesForScope =
        scope:
        let
          dir = "${lintingDir}/${scope}";
        in
        if builtins.pathExists dir then
          lib.mapAttrsToList (name: _: {
            src = "${dir}/${name}";
            dest = name;
            initialOnly = isInitialOnly name;
          }) (builtins.readDir dir)
        else
          [ ];

      dartFiles = lib.optionals cfg.dart (filesForScope "dart");
      flutterFiles = lib.optionals cfg.flutter (filesForScope "flutter");
      rustFiles = lib.optionals cfg.rust (filesForScope "rust");
      pythonFiles = lib.optionals cfg.python (filesForScope "python");
      typescriptFiles = lib.optionals cfg.typescript (filesForScope "typescript");

    in
    {
      options.famedly.standards.linting = {
        enable = lib.mkEnableOption "linting configurations";

        dart = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Sync Dart linting configuration (analysis_options.yaml).";
        };

        flutter = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Sync Flutter linting configuration (analysis_options.yaml for Flutter).";
        };

        rust = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Sync Rust linting configuration (clippy.toml, rustfmt.toml, .cargo/).";
        };

        python = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Sync Python linting configuration (ruff.toml).";
        };

        typescript = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Sync TypeScript linting configuration (eslint.config.base.mjs).";
        };
      };

      config = lib.mkIf cfg.enable {
        famedly.standards._internal.managedFiles =
          dartFiles ++ flutterFiles ++ rustFiles ++ pythonFiles ++ typescriptFiles;
      };
    }
  );
}
