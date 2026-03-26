# flake.nix template for Flutter + Rust monorepos.
# Copy this file to your repo root and adjust as needed.
#
# Expected directory structure:
#   ├── flake.nix           (this file)
#   ├── frontend/           (Flutter app)
#   │   ├── pubspec.yaml
#   │   ├── lib/
#   │   └── test/
#   └── backend/            (Rust service)
#       ├── Cargo.toml
#       └── src/
#
# The flake uses the projects abstraction to scope linting configs,
# Dependabot entries, and pre-commit hooks to their respective directories.
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
          toolchain = inputs.fenix.packages.${system}.stable.toolchain;
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;

          nightlyToolchain = inputs.fenix.packages.${system}.latest.toolchain;
          craneLibNightly = (inputs.crane.mkLib pkgs).overrideToolchain nightlyToolchain;

          rustSrc = craneLib.cleanCargoSource ./backend;
          commonArgs = {
            src = rustSrc;
            strictDeps = true;
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          famedly.standards = {
            # AI rules for both languages
            rules = {
              enable = true;
              extraScopes = [
                "rust"
                "dart"
                "flutter"
              ];
            };

            checks.enable = true;
            ci = {
              enable = true;
              armRunners = false;
            };
            infrastructure = {
              editorconfig = true;
              dependabot = true;
            };
            devShell.enable = true;

            # Monorepo project definitions — each gets scoped linting,
            # Dependabot, and pre-commit hooks in its directory.
            projects = {
              backend = {
                language = "rust";
                directory = "backend";
              };
              frontend = {
                language = "flutter";
                directory = "frontend";
              };
            };

            # Hooks need to be enabled for project hook entries to take effect.
            hooks.enable = true;

            # Workflow files (repo-level)
            workflows = {
              conventionalCommits = true;
              authenticateCommits = false;
              # Reusable rust-ci expects Cargo at repo root. This layout uses backend/;
              # use `nix flake check` for Rust, or add a root workspace / extend rust-ci.
              rustCi.enable = false;
              # dartCi.enable is auto-set by dart.enable; only directory needs overriding
              dartCi.directory = "frontend";
              # rustPublish.enable = true;       # uncomment for crate publishing
              # dockerBackend = {                # uncomment for Docker builds
              #   enable = true;
              #   targets = "backend-service";
              # };
              # fastForward = true;              # uncomment for /fast-forward PR merges
            };

            dart = {
              enable = true;
              flutter = true;
            };
          };

          # Rust-specific checks via crane.
          checks = {
            clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-features --all-targets -- --deny warnings";
              }
            );

            fmt = craneLibNightly.cargoFmt { src = rustSrc; };

            tests = craneLib.cargoNextest (commonArgs // { inherit cargoArtifacts; });

            deny = craneLib.cargoDeny { src = rustSrc; };
          };

          packages.default = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

          devShells.default = pkgs.mkShell {
            inputsFrom =
              lib.optionals (config.famedly.standards.devShell.enable && config.devShells ? famedly-standards) [
                config.devShells.famedly-standards
              ]
              ++ [ (craneLib.devShell { }) ];
            packages = [
              pkgs.flutter
              pkgs.cargo-watch
              pkgs.cargo-edit
              pkgs.cargo-deny
            ];
          };
        };
    };
}
