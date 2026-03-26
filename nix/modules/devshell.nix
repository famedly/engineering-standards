# DevShell module: adds standard development tools to `nix develop`.
#
# Consumer repos that enable this get these tools in their dev shell:
#   - pre-commit (for running hooks locally)
#   - typos (spell checker)
#   - reuse (license compliance)
#   - nixfmt-classic (Nix formatter)
#
# Language-specific toolchains (Dart SDK, Rust/fenix, etc.) are the
# responsibility of the consumer repo's own devShell configuration.

{ flake-parts-lib, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.devShell;
    in
    {
      options.famedly.standards.devShell = {
        enable = lib.mkEnableOption "shared dev shell tools";

        preCommit = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Include pre-commit in the dev shell.";
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional packages to add to the dev shell.";
        };
      };

      config = lib.mkIf cfg.enable {
        devShells.famedly-standards = pkgs.mkShell {
          name = "famedly-standards";
          packages = [
            pkgs.typos
            pkgs.nixfmt-classic
            pkgs.reuse
          ]
          ++ lib.optionals cfg.preCommit [ pkgs.pre-commit ]
          ++ cfg.extraPackages;
        };
      };
    }
  );
}
