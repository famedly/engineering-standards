# flake.nix template for Rust repositories.
# Copy this file to your repo root and adjust as needed.
#
# Uses crane + fenix for Rust builds: the recommended approach for
# Nix-first Rust development.
{
  description = "REPLACE_WITH_REPO_DESCRIPTION";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    engineering-standards.url = "github:famedly/engineering-standards";
    crane.url = "github:ipetkov/crane";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
          system,
          ...
        }:
        let
          # Stable toolchain for builds, clippy, and tests.
          toolchain = inputs.fenix.packages.${system}.stable.toolchain;
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;

          # Nightly toolchain for rustfmt and cargo-udeps.
          nightlyToolchain = inputs.fenix.packages.${system}.latest.toolchain;
          craneLibNightly = (inputs.crane.mkLib pkgs).overrideToolchain nightlyToolchain;

          src = craneLib.cleanCargoSource ./.;
          commonArgs = {
            inherit src;
            strictDeps = true;
          };

          # Build dependencies separately for caching.
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          famedly.standards = {
            rules = {
              enable = false;
              extraScopes = [ "rust" ];
            };
            linting = {
              enable = true;
              rust = true; # clippy.toml, rustfmt.toml, .cargo/
            };
            hooks = {
              enable = true;
              rust = true; # cargo fmt + cargo clippy pre-commit hooks
            };
            checks.enable = true;
            infrastructure = {
              editorconfig = true;
              dependabot = true;
              dependabotRust = true;
            };
            ci = {
              enable = true;
              # true only if your GitHub org provides Famedly ARM runners
              armRunners = false;
            };
            devShell.enable = true;

            # Workflow files (generated as thin callers of reusable workflows)
            workflows = {
              conventionalCommits = true;
              # Enable if your org uses OpenPGP commit authentication
              authenticateCommits = false;
              rustCi.enable = true;
              # rustPublish.enable = true;       # uncomment for crate publishing
              # dockerBackend.enable = true;     # uncomment for Docker builds
              # fastForward = true;              # uncomment for /fast-forward PR merges
            };
          };

          # Rust-specific checks via crane.
          checks = {
            # cargo clippy — all features, all targets, deny warnings
            clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-features --all-targets -- --deny warnings";
              }
            );

            # cargo fmt check (nightly for unstable formatting options)
            fmt = craneLibNightly.cargoFmt { inherit src; };

            # cargo nextest (fast parallel test runner)
            tests = craneLib.cargoNextest (commonArgs // { inherit cargoArtifacts; });

            # cargo deny — license/advisory/duplicate dependency audit.
            # deny.toml is synced from engineering-standards via linting.rust = true.
            deny = craneLib.cargoDeny { inherit src; };
          };

          # Default package
          packages.default = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

          # Dev shell: famedly-standards tools (pre-commit, typos, …) + crane toolchain
          devShells.default = pkgs.mkShell {
            inputsFrom =
              lib.optionals (config.famedly.standards.devShell.enable && config.devShells ? famedly-standards) [
                config.devShells.famedly-standards
              ]
              ++ [ (craneLib.devShell { }) ];
            packages = with pkgs; [
              cargo-watch
              cargo-edit
              cargo-deny
            ];
          };
        };
    };
}
