# Rules module: syncs AI rules to .cursor/rules/standards/ and generates CLAUDE.md.
#
# Rules are markdown files in the engineering-standards repo under ai-rules/.
# They are structured as:
#   ai-rules/global/      — apply to all repos
#   ai-rules/dart/        — Dart-specific rules
#   ai-rules/flutter/     — Flutter-specific rules (superset of Dart)
#   ai-rules/rust/        — Rust-specific rules
#
# Generated files in consumer repo:
#   .cursor/rules/standards/*.md   (one file per rule)
#   CLAUDE.md                      (all active rules concatenated)

{ flake-parts-lib, lib, ... }:
let
  root = ../..;
  rulesDir = "${root}/ai-rules";

  # List all .md files in a rules subdirectory, returning (filename, path) pairs.
  rulesForScope =
    scope:
    let
      dir = "${rulesDir}/${scope}";
      hasMd = lib.hasSuffix ".md";
    in
    if builtins.pathExists dir then
      lib.mapAttrsToList (name: _: {
        inherit name;
        path = "${dir}/${name}";
      }) (lib.filterAttrs (n: _: hasMd n) (builtins.readDir dir))
    else
      [ ];
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
      cfg = config.famedly.standards.rules;
      activeScopes = [ "global" ] ++ cfg.extraScopes;
      allRules = lib.concatMap rulesForScope activeScopes;

      # Concatenate all rule files into CLAUDE.md
      claudeMd = pkgs.runCommand "CLAUDE.md" { } ''
        cat ${lib.concatMapStringsSep " " (r: r.path) allRules} > $out
      '';
    in
    {
      options.famedly.standards.rules = {
        enable = lib.mkEnableOption "AI rules (Cursor rules + CLAUDE.md)";

        extraScopes = lib.mkOption {
          type = lib.types.listOf (
            lib.types.enum [
              "dart"
              "flutter"
              "nix"
              "rust"
              "python"
              "typescript"
            ]
          );
          default = [ ];
          description = ''
            Language-specific rule scopes to include in addition to global rules.
            Global rules are always included. Use "flutter" for Flutter projects
            (includes Flutter-specific architecture and widget rules).
          '';
          example = [
            "rust"
            "dart"
            "flutter"
          ];
        };
      };

      config = lib.mkIf cfg.enable {
        famedly.standards._internal.managedFiles =
          # One entry per rule file → .cursor/rules/standards/<name>
          (map (r: {
            src = r.path;
            dest = ".cursor/rules/standards/${r.name}";
          }) allRules)
          # Plus the concatenated CLAUDE.md
          ++ [
            {
              src = claudeMd;
              dest = "CLAUDE.md";
            }
          ];
      };
    }
  );
}
