# flake.nix template for Flutter repositories.
# Copy this file to your repo root and adjust as needed.
#
# Note: Flutter builds are NOT fully Nixified (complex native dependencies).
# The flake provides the dev shell, CI checks (analyze, format, test),
# and standards management. Build/release still uses flutter build.
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
              extraScopes = [
                "dart"
                "flutter"
              ];
            };
            linting = {
              enable = true;
              flutter = true; # Generates analysis_options.yaml (Flutter variant)
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
              # dartReviewApp = {                # uncomment for review app deployment
              #   enable = true;
              #   projectName = "my-app";
              # };
              # docker.enable = true;            # uncomment for multi-arch Docker builds
              # githubPages.enable = true;       # uncomment for GitHub Pages deployment
            };

            dart = {
              enable = true;
              flutter = true; # Use Flutter SDK; also enables dart-ci.yml workflow
            };
          };

          devShells.default = pkgs.mkShell {
            inputsFrom = lib.optionals (
              config.famedly.standards.devShell.enable && config.devShells ? famedly-standards
            ) [ config.devShells.famedly-standards ];
            packages = [ pkgs.flutter ];
          };
        };
    };
}
