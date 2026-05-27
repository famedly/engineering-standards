{
  flakeModules,
  inputs,
  flake-parts-lib,
  lib,
  ...
}:
importingFlake: {
  imports = [ flakeModules.prek-pre-commit ];

  config.perSystem =
    {
      self',
      pkgs,
      config,
      ...
    }:
    let
      cargo = lib.getExe' self'.packages.famedly-rust-toolchain "cargo";
    in
    {
      prek-pre-commit.workspaces = lib.mapAttrs (name: _: {
        default_language_version.rust = "system";

        repos = [
          {
            repo = "local";
            hooks = [
              {
                id = "clippy";
                name = "clippy";
                description = "Run clippy on all targets";

                entry = "${cargo} clippy --workspace --all-targets -- -D warnings";

                language = "rust";
                types = [ "rust" ];
                pass_filenames = false;
              }

              # TODO: Assuming we use treefmt-nix, this might not be
              # needed
              {
                id = "rustfmt";
                name = "rustfmt";
                description = "Run rustfmt against all packages";

                entry = "${cargo} fmt --all --check";

                language = "rust";
                types = [ "rust" ];
                pass_filenames = false;
              }

              {
                id = "cargo-lock";
                name = "cargo-lock";
                description = "Ensures the `Cargo.lock` is up to date";

                entry = "${cargo} update --offline --workspace --locked";

                language = "rust";

                # TODO: In newer prek versions, a `glob` attribute is
                # supported, which looks much nicer:
                #
                # files.glob = [
                #   "Cargo.toml"
                #   "Cargo.lock"
                # ];
                files = "Cargo\\.toml|Cargo\\.lock";

                pass_filenames = false;
              }
            ];
          }
        ];
      }) config.famedly.standards.rust.projects;
    };
}
