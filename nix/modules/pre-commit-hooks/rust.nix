{
  lib,
  flake-parts-lib,
  moduleWithSystem,
  ...
}:
importingFlake: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.preCommitHooks.rustHooks.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Rust hooks (clippy, rustfmt, cargo lockfile) at the repo root.";
    };
  });

  config.perSystem = moduleWithSystem (
    { self', ... }:
    { config, ... }:
    let
      cfg = config.famedly.standards.preCommitHooks;
    in
    lib.mkIf cfg.rustHooks.enable {
      pre-commit.settings = {
        tools = {
          cargo = self'.packages.famedly-rust-toolchain;
          clippy = self'.packages.famedly-rust-toolchain;
          rustfmt = self'.packages.famedly-rust-toolchain;
        };

        cargo-lock = {
          enable = true;
          name = "cargo lockfile";
          description = "Ensures the `Cargo.lock` is up to date";
          package = config.pre-commit.settings.tools.cargo;
          entry = "${lib.getExe config.pre-commit.settings.hooks.cargo-lock.package} update --offline --workspace --locked";
          language = "system";
          pass_filenames = false;
        };

        hooks = {
          clippy = {
            enable = true;
            settings = {
              denyWarnings = true;
              extraArgs = lib.escapeShellArgs [
                "--workspace"
                "--all-targets"
              ];
            };
          };

          rustfmt = {
            enable = true;
            settings.check = true;
          };
        };
      };
    }
  );
}
