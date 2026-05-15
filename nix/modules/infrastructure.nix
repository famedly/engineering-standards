# Infrastructure module: manages EditorConfig and Dependabot configuration.
#
# Generated files in consumer repo:
#   .editorconfig               — standard editor settings
#   .github/dependabot.yml      — dependency update configuration
#
# Dependabot entries come from two sources:
#   1. Flat options here (dependabotRust, dependabotDart, etc.)
#   2. The projects module (_internal.dependabotEntries)
# Both are merged into a single dependabot.yml.

{ flake-parts-lib, ... }:
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
      cfg = config.famedly.standards.infrastructure;
      allEntries = config.famedly.standards._internal.dependabotEntries;

      needsGitRegistry = lib.any (e: e.ecosystem == "cargo" || e.ecosystem == "pub") allEntries;
      needsNpmRegistry = lib.any (e: e.ecosystem == "npm") allEntries;
      needsAnyRegistry = needsGitRegistry || needsNpmRegistry;

      # github-actions entry — always included, uses pattern-based grouping.
      renderGHA = lib.concatStringsSep "\n" [
        "  - package-ecosystem: \"github-actions\""
        "    directory: \"/\""
        "    schedule:"
        "      interval: \"daily\""
        "      timezone: \"Europe/Berlin\""
        "    groups:"
        "      actions:"
        "        patterns: [\"*\"]"
        "    commit-message:"
        "      prefix: \"chore(deps): \""
      ];

      # Render a language/tool ecosystem entry.
      # Uses explicit strings to preserve indentation under `updates:`.
      renderEntry =
        entry:
        let
          eco = entry.ecosystem;
          dir = entry.directory;
          usesGitRegistry = eco == "cargo" || eco == "pub";
          usesNpmRegistry = eco == "npm";
          supportsSemver = eco != "docker" && eco != "terraform";
        in
        lib.concatStringsSep "\n" (
          [
            ""
            "  - package-ecosystem: \"${eco}\""
            "    directory: \"${dir}\""
            "    schedule:"
            "      interval: \"daily\""
            "      timezone: \"Europe/Berlin\""
            "    open-pull-requests-limit: 10"
          ]
          ++ lib.optionals usesGitRegistry [
            "    registries:"
            "      - private-github"
          ]
          ++ lib.optionals usesNpmRegistry [
            "    registries:"
            "      - private-github-npm"
          ]
          ++ lib.optionals (eco != "pub") [ # For pub we prefer to have single PRs per dependency bump
            "    groups:"
            "      major:"
            "        update-types: [\"major\"]"
            "      minor-and-patch:"
            "        update-types: [\"minor\", \"patch\"]"
          ]
          ++ [
            "    commit-message:"
            "      prefix: \"chore(deps): \""
            "      include: \"scope\""
            "    cooldown:"
            "      default-days: 14"
          ]
          ++ lib.optionals supportsSemver [
            "      semver-major-days: 14"
          ]
        )
        + "\n";

      dependabotYaml = pkgs.writeText "dependabot.yml" (
        lib.concatStringsSep "\n" (
          [
            "# managed-by: engineering-standards — do not edit manually"
            "# Regenerate with: nix run .#regenerateStandards"
            "version: 2"
          ]
          ++ lib.optionals needsAnyRegistry (
            [ "registries:" ]
            ++ lib.optionals needsGitRegistry [
              "  private-github:"
              "    type: git"
              "    url: https://github.com"
              "    username: x-access-token"
              "    password: \${{secrets.DEPENDABOT_SECRET}}"
            ]
            ++ lib.optionals needsNpmRegistry [
              "  private-github-npm:"
              "    type: npm-registry"
              "    url: https://npm.pkg.github.com"
              "    token: \${{secrets.DEPENDABOT_SECRET}}"
            ]
          )
          ++ [
            "updates:"
            renderGHA
          ]
        )
        + "\n"
        + lib.concatMapStrings renderEntry allEntries
      );
    in
    {
      options.famedly.standards.infrastructure = {
        editorconfig = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Sync standard .editorconfig.";
        };

        dependabot = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Sync .github/dependabot.yml.";
        };

        dependabotDart = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include Dart/pub ecosystem in Dependabot.";
        };

        dependabotRust = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include Rust/cargo ecosystem in Dependabot.";
        };

        dependabotPython = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include Python/pip ecosystem in Dependabot.";
        };

        dependabotDocker = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include Docker ecosystem in Dependabot.";
        };

        dependabotNpm = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include npm ecosystem with private GitHub registry in Dependabot.";
        };

        dependabotTerraform = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include Terraform ecosystem in Dependabot.";
        };
      };

      config = {
        # Flat options push entries into the shared internal list.
        famedly.standards._internal.dependabotEntries =
          lib.optionals cfg.dependabotDart [
            {
              ecosystem = "pub";
              directory = "/";
            }
          ]
          ++ lib.optionals cfg.dependabotRust [
            {
              ecosystem = "cargo";
              directory = "/";
            }
          ]
          ++ lib.optionals cfg.dependabotPython [
            {
              ecosystem = "pip";
              directory = "/";
            }
          ]
          ++ lib.optionals cfg.dependabotDocker [
            {
              ecosystem = "docker";
              directory = "/";
            }
          ]
          ++ lib.optionals cfg.dependabotNpm [
            {
              ecosystem = "npm";
              directory = "/";
            }
          ]
          ++ lib.optionals cfg.dependabotTerraform [
            {
              ecosystem = "terraform";
              directory = "/";
            }
          ];

        famedly.standards._internal.managedFiles =
          lib.optionals cfg.editorconfig [
            {
              src = "${root}/linting/editorconfig";
              dest = ".editorconfig";
            }
          ]
          ++ lib.optionals cfg.dependabot [
            {
              src = dependabotYaml;
              dest = ".github/dependabot.yml";
            }
          ];
      };
    }
  );
}
