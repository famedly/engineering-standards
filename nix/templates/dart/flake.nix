# flake.nix template for Dart repositories.
# Copy this file to your repo root and adjust as needed.
#
# After adding:
#   nix flake update
#   nix run .#regenerateStandards
#   nix flake check
{
  description = "REPLACE_WITH_REPO_DESCRIPTION";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    engineering-standards.url = "github:famedly/engineering-standards";
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.engineering-standards.flakeModules.default ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          pkgs,
          lib,
          ...
        }:
        {
          famedly.standards = {
            rules = {
              enable = false;
              extraScopes = [ "dart" ];
            };
            linting = {
              enable = true;
              dart = true; # Generates analysis_options.yaml
            };
            hooks = {
              enable = true;
              dart = true; # dart format + dart analyze pre-commit hooks
            };
            checks.enable = true;
            infrastructure = {
              editorconfig = true;
              dependabot = true;
              dependabotDart = true;
            };
            ci = {
              enable = true;
              armRunners = false;
            };
            devShell.enable = true;

            # Workflow files (generated as thin callers of reusable workflows)
            workflows = {
              conventionalCommits = true;
              authenticateCommits = false;
              # dartCi is auto-enabled by dart.enable below
              # dartPublish.enable = true;       # uncomment for pub.dev publishing
            };

            # Dart SDK in nix develop; also enables dart-ci.yml workflow
            dart = {
              enable = true;
              flutter = false; # Set to true for Flutter projects
            };
          };

          devShells.default = pkgs.mkShell {
            inputsFrom = lib.optionals (
              config.famedly.standards.devShell.enable && config.devShells ? famedly-standards
            ) [ config.devShells.famedly-standards ];
            packages = [ pkgs.dart ];
          };
        };
    };
}
