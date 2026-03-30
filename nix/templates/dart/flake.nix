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
            rules.enable = false;
            linting = {
              enable = true;
              dart = true;
            };
            preCommitHooks = {
              enable = true;
              dartHooks.enable = true;
            };
            infrastructure = {
              editorconfig = true;
              dependabot = true;
              dependabotDart = true;
            };
            devShell.enable = true;

            dart = {
              enable = true;
              flutter = false;
            };
          };

          famedly.github.workflows = {
            ci = {
              enable = true;
              armRunners = false;
            };
            "general-checks".enable = true;
            "ai-review".enable = false;
            # dart-ci is auto-enabled by dart.enable above
            # dart-ci.test = true;               # uncomment for test job
            # dart-ci.coverage = true;            # uncomment for coverage + Codecov
            # dart-ci.coverageFlags = "";         # Codecov flags (e.g. "unit-tests")
            # "publish-pub".enable = true;        # uncomment for pub.dev publishing
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
