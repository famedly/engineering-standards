# Hooks module: generates .pre-commit-config.yaml.
#
# Composes a pre-commit configuration from:
#   hooks/base.yaml      — always included when hooks are enabled
#   hooks/dart.yaml      — added when hooks.dart = true or via projects
#   hooks/rust.yaml      — added when hooks.rust = true or via projects
#   hooks/python.yaml    — added when hooks.python = true or via projects
#
# Hook entries come from two sources:
#   1. Flat options here (hooks.rust, hooks.dart, hooks.python)
#   2. The projects module (_internal.hookEntries)
#
# Hooks with a non-empty directory get scoped: file patterns restrict
# triggering, and entry commands cd into the project directory.

{ flake-parts-lib, lib, ... }:
let
  root = ../..;
  hooksDir = "${root}/hooks";
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
      cfg = config.famedly.standards.hooks;
      allEntries = config.famedly.standards._internal.hookEntries;

      # Partition entries into root-level (use static YAML) and
      # directory-scoped (generate modified YAML).
      rootEntries = builtins.filter (e: e.directory == "") allEntries;
      scopedEntries = builtins.filter (e: e.directory != "") allEntries;

      # Static YAML files for root-level hooks (the original approach).
      rootHookFiles = [
        "${hooksDir}/base.yaml"
      ]
      ++ lib.optionals (lib.any (e: e.scope == "dart") rootEntries) [
        "${hooksDir}/dart.yaml"
      ]
      ++ lib.optionals (lib.any (e: e.scope == "rust") rootEntries) [
        "${hooksDir}/rust.yaml"
      ]
      ++ lib.optionals (lib.any (e: e.scope == "python") rootEntries) [
        "${hooksDir}/python.yaml"
      ];

      # Generate YAML for directory-scoped hooks. Uses explicit strings
      # to avoid Nix multiline-string indentation stripping — the output
      # must match the 2-space indentation of the static YAML files.
      scopedRustYaml =
        entry:
        let
          slug = lib.replaceStrings [ "/" ] [ "-" ] entry.directory;
          dir = entry.directory;
        in
        lib.concatStringsSep "\n" [
          "  - repo: local"
          "    hooks:"
          "      - id: cargo-fmt-${slug}"
          "        name: \"cargo fmt (${dir})\""
          "        entry: bash -c 'cd ${dir} && cargo +nightly fmt -- --check'"
          "        language: system"
          "        types: [rust]"
          "        files: ^${dir}/"
          "      - id: cargo-clippy-${slug}"
          "        name: \"cargo clippy (${dir})\""
          "        entry: bash -c 'cd ${dir} && cargo clippy --workspace --all-targets -- -D warnings'"
          "        language: system"
          "        types: [rust]"
          "        pass_filenames: false"
          "        files: ^${dir}/"
          "      - id: cargo-lock-${slug}"
          "        name: \"cargo lockfile (${dir})\""
          "        entry: bash -c 'cd ${dir} && cargo check'"
          "        language: system"
          "        pass_filenames: false"
          "        types: [rust]"
          "        files: ^${dir}/"
        ]
        + "\n";

      scopedDartYaml =
        entry:
        let
          slug = lib.replaceStrings [ "/" ] [ "-" ] entry.directory;
          dir = entry.directory;
        in
        lib.concatStringsSep "\n" [
          "  - repo: local"
          "    hooks:"
          "      - id: dart-format-${slug}"
          "        name: \"dart format (${dir})\""
          "        entry: bash -c 'cd ${dir} && dart format'"
          "        language: system"
          "        types: [dart]"
          "        files: ^${dir}/"
          "      - id: dart-analyze-${slug}"
          "        name: \"dart analyze (${dir})\""
          "        entry: bash -c 'cd ${dir} && dart analyze --fatal-infos'"
          "        language: system"
          "        types: [dart]"
          "        pass_filenames: false"
          "        files: ^${dir}/"
        ]
        + "\n";

      scopedPythonYaml =
        entry:
        let
          slug = lib.replaceStrings [ "/" ] [ "-" ] entry.directory;
          dir = entry.directory;
        in
        lib.concatStringsSep "\n" [
          "  - repo: local"
          "    hooks:"
          "      - id: ruff-check-${slug}"
          "        name: \"ruff check (${dir})\""
          "        entry: bash -c 'cd ${dir} && ruff check --fix'"
          "        language: system"
          "        types: [python]"
          "        files: ^${dir}/"
          "      - id: ruff-format-${slug}"
          "        name: \"ruff format (${dir})\""
          "        entry: bash -c 'cd ${dir} && ruff format'"
          "        language: system"
          "        types: [python]"
          "        files: ^${dir}/"
        ]
        + "\n";

      scopedYaml =
        entry:
        if entry.scope == "rust" then
          scopedRustYaml entry
        else if entry.scope == "dart" then
          scopedDartYaml entry
        else if entry.scope == "python" then
          scopedPythonYaml entry
        else
          "";

      scopedHooksFile = pkgs.writeText "scoped-hooks.yaml" (
        lib.concatMapStrings scopedYaml scopedEntries
      );

      preCommitConfig = pkgs.runCommand "pre-commit-config.yaml" { } ''
        echo "repos:" > $out
        ${lib.concatMapStrings (f: ''
          grep -v '^repos:' ${f} >> $out || true
        '') rootHookFiles}
        cat ${scopedHooksFile} >> $out
      '';
    in
    {
      options.famedly.standards.hooks = {
        enable = lib.mkEnableOption "pre-commit hooks";

        dart = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include Dart-specific pre-commit hooks.";
        };

        rust = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include Rust-specific pre-commit hooks (cargo fmt, clippy).";
        };

        python = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include Python-specific pre-commit hooks (ruff).";
        };
      };

      config = lib.mkIf cfg.enable {
        # Flat options push entries into the shared internal list.
        famedly.standards._internal.hookEntries =
          lib.optionals cfg.dart [
            {
              scope = "dart";
              directory = "";
            }
          ]
          ++ lib.optionals cfg.rust [
            {
              scope = "rust";
              directory = "";
            }
          ]
          ++ lib.optionals cfg.python [
            {
              scope = "python";
              directory = "";
            }
          ];

        famedly.standards._internal.managedFiles = [
          {
            src = preCommitConfig;
            dest = ".pre-commit-config.yaml";
          }
        ];
      };
    }
  );
}
