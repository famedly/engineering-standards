# CI Workflow module: generates a minimal .github/workflows/ci.yml.
#
# Following the nehws pattern: the CI workflow is just a Nix runner.
# All build/test/lint logic lives in `nix flake check`.
#
# The generated ci.yml:
#   1. Checks out the repo
#   2. Installs Nix
#   3. Sets up Cachix
#   4. Runs `nix flake check`

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
      cfg = config.famedly.standards.ci;
      pinData = import ../action-versions-data.nix;
      checkoutPin = pinData.checkout;
      installNixPin = pinData.installNix;
      cachixPin = pinData.cachixAction;

      runsOn = if cfg.armRunners then "arm-ubuntu-latest-8core" else "ubuntu-latest";

      ciYaml = pkgs.writeText "ci.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: CI
        on:
          push:
            branches: ["main"]
            tags: ["*"]
          pull_request:
            branches: ["**"]
            types:
              - opened
              - reopened
              - synchronize
              - ready_for_review
          merge_group:

        concurrency:
          group: ''${{ github.workflow }}-''${{ github.ref }}
          cancel-in-progress: ''${{ github.ref != 'refs/heads/main' }}

        jobs:
          nix-checks:
            name: "Nix checks"
            runs-on: ${runsOn}
            steps:
              - uses: actions/checkout@${checkoutPin.sha} # ${checkoutPin.v}
              - uses: cachix/install-nix-action@${installNixPin.sha} # ${installNixPin.v}
                with:
                  extra_nix_config: |
                    experimental-features = nix-command flakes
              - uses: cachix/cachix-action@${cachixPin.sha} # ${cachixPin.v}
                with:
                  name: famedly
                  signingKey: "''${{ secrets.CACHIX_SIGNING_KEY_FAMEDLY }}"
                  authToken: "''${{ secrets.CACHIX_AUTH_TOKEN_FAMEDLY }}"
                continue-on-error: true
              - name: Run all checks
                run: nix flake check -L
      '';
    in
    {
      options.famedly.standards.ci = {
        enable = lib.mkEnableOption "generate standard CI workflow";

        armRunners = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Use Famedly ARM runners instead of standard ubuntu-latest.";
        };
      };

      config = lib.mkIf cfg.enable {
        famedly.standards._internal.managedFiles = [
          {
            src = ciYaml;
            dest = ".github/workflows/ci.yml";
          }
        ];
      };
    }
  );
}
