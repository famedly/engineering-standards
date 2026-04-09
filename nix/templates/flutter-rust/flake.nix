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
# Dependabot entries, and pre-commit hooks to their directories.
# The rust module generates all Rust checks, packages, and dev shell.
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
          pkgs,
          lib,
          system,
          ...
        }:
        let
          fenixPkgs = inputs.fenix.packages.${system};

          # Combined toolchain: stable Rust + nightly rustfmt.
          toolchain = fenixPkgs.combine [
            fenixPkgs.stable.cargo
            fenixPkgs.stable.clippy
            fenixPkgs.stable.rust-src
            fenixPkgs.stable.rustc
            fenixPkgs.latest.rustfmt
          ];
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;
        in
        {
          famedly.standards = {
            rules.enable = false;
            preCommitHooks.enable = true;
            infrastructure = {
              editorconfig = true;
              dependabot = true;
            };
            devShell.enable = true;

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

            dart = {
              enable = true;
              flutter = true;
            };

            rust = {
              enable = true;
              inherit craneLib;
              src = ./backend;
              devShell.extraPackages = [ pkgs.flutter ];
              # checks.clippy.useTestSrc = true;  # uncomment if tests use include_str!/include_bytes!
              # docker.enable = true;              # uncomment for Docker image
            };
          };

          famedly.github.workflows = {
            ci = {
              enable = true;
              armRunners = false;
            };
            "general-checks".enable = true;
            "ai-review".enable = false;
            # rust-ci expects Cargo at repo root; this layout uses backend/
            "rust-ci".enable = false;
            # dart-ci is auto-enabled by dart.enable; only directory needs overriding
            "dart-ci".directory = "frontend";
            # "publish-crate".enable = true;     # uncomment for crate publishing
            # "docker-backend" = {               # uncomment for Docker builds
            #   enable = true;
            #   targets = "backend-service";
            # };
            # "fast-forward".enable = true;      # uncomment for /fast-forward PR merges
          };
        };
    };
}
