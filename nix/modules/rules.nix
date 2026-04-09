# Rules module: placeholder for AI rules.
#
# The full ai-rules content is currently disabled.  When enabled this
# module writes a single placeholder CLAUDE.md so that consumer repos
# with `rules.enable = true` keep working without error.

{ flake-parts-lib, ... }:
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

      placeholder = pkgs.writeText "CLAUDE.md" ''
        # Engineering Standards — AI Rules

        AI rules are not yet available. This file is a placeholder.
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
            Currently a no-op — reserved for future use.
          '';
          example = [
            "rust"
            "dart"
            "flutter"
          ];
        };
      };

      config = lib.mkIf cfg.enable {
        famedly.standards._internal.managedFiles = [
          {
            src = placeholder;
            dest = "CLAUDE.md";
          }
        ];
      };
    }
  );
}
