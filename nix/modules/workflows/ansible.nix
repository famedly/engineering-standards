# Ansible workflow module: generates caller workflow for Ansible CI.
#
# Generated files in consumer repo:
#   .github/workflows/ansible-ci.yml — lint, test, and format Ansible collections

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
      cfg = config.famedly.standards.workflows.ansible;
      ref = config.famedly.standards.workflowRef;

      ansibleCiYaml = pkgs.writeText "ansible-ci.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Ansible CI
        on:
          push:
            branches: ["main"]
          pull_request:
            branches: ["**"]
            types: [opened, reopened, synchronize]

        jobs:
          ci:
            uses: famedly/engineering-standards/.github/workflows/ansible-ci.yml@${ref}
            with:
              collection: ${cfg.collection}
      '';
    in
    {
      options.famedly.standards.workflows.ansible = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate Ansible CI workflow.";
        };

        collection = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Ansible collection name (e.g. famedly.dns).";
          example = "famedly.dns";
        };
      };

      config = {
        famedly.standards._internal.managedFiles = lib.optionals cfg.enable [
          {
            src = ansibleCiYaml;
            dest = ".github/workflows/ansible-ci.yml";
          }
        ];
      };
    }
  );
}
