# Checks module: contributes shared quality checks to `nix flake check`.
#
# Consumer repos import the engineering-standards flake module and enable:
#   famedly.standards.checks.enable = true;
#
# This adds the following to `nix flake check`:
#   checks.famedly-typos   — typos spell checker (runs against consumer repo src)
#   checks.famedly-reuse   — REUSE license compliance
#
# The consumer's source is accessed via `self.outPath` which flake-parts
# provides as the root of the consumer's flake.

{
  flake-parts-lib,
  lib,
  self,
  ...
}:
let
  root = ../..;
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
      cfg = config.famedly.standards.checks;
      # self.outPath is the consumer repo's source root (not engineering-standards).
      # This is what we want to check for typos, license compliance, etc.
      consumerSrc = self.outPath;
    in
    {
      options.famedly.standards.checks = {
        enable = lib.mkEnableOption "shared quality checks (typos, reuse)";

        typos = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable typos spell checker on the consumer repo source.";
        };

        reuse = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable REUSE license compliance check.";
        };

        typosConfig = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to a typos config file (e.g. ./typos.toml).
            When null, the engineering-standards default config is used.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        checks =
          lib.optionalAttrs cfg.typos {
            famedly-typos =
              let
                typosConf = if cfg.typosConfig != null then cfg.typosConfig else "${root}/nix/typos.toml";
              in
              pkgs.runCommand "famedly-typos" { } ''
                ${lib.getExe pkgs.typos} --config ${typosConf} ${consumerSrc}
                touch $out
              '';
          }
          // lib.optionalAttrs cfg.reuse {
            famedly-reuse =
              pkgs.runCommand "famedly-reuse"
                {
                  buildInputs = [ pkgs.reuse ];
                }
                ''
                  cd ${consumerSrc}
                  reuse lint
                  touch $out
                '';
          };
      };
    }
  );
}
