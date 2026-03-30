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
          fenixPkgs = inputs.fenix.packages.${system};

          # Combined toolchain: stable Rust + nightly rustfmt.
          # Nightly rustfmt is required because rustfmt.toml uses unstable
          # options (imports_granularity, group_imports, wrap_comments, …).
          toolchain = fenixPkgs.combine [
            fenixPkgs.stable.cargo
            fenixPkgs.stable.clippy
            fenixPkgs.stable.rust-src
            fenixPkgs.stable.rustc
            fenixPkgs.latest.rustfmt
          ];
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;

          # Filtered source for compilation/clippy/fmt: only Cargo files.
          # Smaller hash → more stable cache keys → faster CI.
          src = craneLib.cleanCargoSource ./.;

          # Full source for tests: preserves all runtime resources (fixtures,
          # config files, scripts, …) that tests may need. Using lib.cleanSource
          # keeps everything except .git and Nix build artefacts, so no per-project
          # file-pattern maintenance is required.
          srcForTests = lib.cleanSource ./.;

          commonArgs = {
            inherit src;
            strictDeps = true;
            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ pkgs.openssl ];
            LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.openssl ];
          };

          # Build dependencies separately for caching.
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          famedly.standards = {
            rules.enable = false;
            linting = {
              enable = true;
              rust = true;
            };
            preCommitHooks = {
              enable = true;
              rustHooks.enable = true;
            };
            infrastructure = {
              editorconfig = true;
              dependabot = true;
              dependabotRust = true;
            };
            devShell.enable = true;
          };

          famedly.github.workflows = {
            ci = {
              enable = true;
              armRunners = false;
            };
            "general-checks".enable = true;
            "ai-review".enable = false;
            "rust-ci".enable = true;
            # "publish-crate".enable = true;     # uncomment for crate publishing
            # "docker-backend".enable = true;    # uncomment for Docker builds
            # "fast-forward".enable = true;      # uncomment for /fast-forward PR merges
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

            # cargo fmt check (toolchain includes nightly rustfmt)
            fmt = craneLib.cargoFmt { inherit src; };

            # cargo nextest (fast parallel test runner).
            # srcForTests includes all runtime resources (fixtures, configs, …).
            tests = craneLib.cargoNextest (
              commonArgs
              // {
                inherit cargoArtifacts;
                src = srcForTests;
                # Uncomment if tests use shell setup scripts (e.g. via nextest [[scripts]]):
                # Nix sandbox only provides /bin/sh; patchShebangs rewrites #!/usr/bin/env bash.
                # cleanSource also strips execute bits, so chmod +x is required.
                # preBuild = ''
                #   find . -name '*.sh' -exec chmod +x {} \;
                #   patchShebangs .
                # '';
              }
            );

            # cargo deny — license/advisory/duplicate dependency audit.
            # deny.toml is synced from engineering-standards via linting.rust = true.
            deny = craneLib.cargoDeny { inherit src; };
          };

          # Default package
          packages.default = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

          # Dev shell: famedly-standards tools (git-hooks.nix, typos, …) + crane toolchain
          devShells.default = pkgs.mkShell {
            inputsFrom =
              lib.optionals (config.famedly.standards.devShell.enable && config.devShells ? famedly-standards) [
                config.devShells.famedly-standards
              ]
              ++ [ (craneLib.devShell { }) ];
            packages = [
              pkgs.cargo-watch
              pkgs.cargo-edit
              pkgs.cargo-deny
            ];
          };
        };
    };
}
