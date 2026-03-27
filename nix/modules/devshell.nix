# DevShell module: adds standard development tools to `nix develop`.
#
# When preCommitHooks are enabled, the devShell composes with
# git-hooks.nix's devShell which provides:
#   - shellHook to auto-install pre-commit hooks on `nix develop`
#   - all hook tool packages (typos, reuse, clippy, etc.)
#
# Language-specific toolchains (Dart SDK, Rust/fenix, etc.) are the
# responsibility of the consumer repo's own devShell configuration.
#
# Generated files in consumer repo:
#   .nixd.json  — nixd language server config for option completion

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
      hooksEnabled = config.famedly.standards.preCommitHooks.enable or false;
      fossEnabled = (config.famedly.standards.preCommitHooks.fossHooks.enable or false) && hooksEnabled;

      nixdJson = pkgs.writeText ".nixd.json" (builtins.toJSON {
        nixpkgs = {
          expr = "import (builtins.getFlake (toString ./.)).inputs.nixpkgs { }";
        };
        options = {
          target = {
            installable = ".#debug.options";
          };
        };
      });
    in
    {
      options.famedly.standards.devShell = {
        enable = lib.mkEnableOption "shared dev shell tools";

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional packages to add to the dev shell.";
        };
      };

      config = lib.mkIf cfg.enable {
        devShells.famedly-standards = pkgs.mkShell {
          name = "famedly-standards";
          inputsFrom = lib.optionals hooksEnabled [
            config.pre-commit.devShell
          ];
          packages = [
            pkgs.nixd
            pkgs.nixfmt-classic
          ]
          ++ lib.optionals fossEnabled [ pkgs.reuse ]
          ++ cfg.extraPackages;
        };

        famedly.standards._internal.managedFiles = [
          {
            src = nixdJson;
            dest = ".nixd.json";
          }
        ];
      };
    }
  );
}
