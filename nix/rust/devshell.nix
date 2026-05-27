{ inputs, ... }:
importingFlake: {
  imports = [ inputs.devenv.flakeModule ];

  perSystem =
    {
      config,
      lib,
      self',
      pkgs,
      system,
      ...
    }:
    lib.mkMerge [
      {
        devshells.rust = {
          packages = lib.attrValues {
            inherit (pkgs)
              # We have some projects that use cargo workspaces, this tool makes
              # matching up dependencies between subcrates easier.
              cargo-autoinherit

              # We use nextest for testing, this cargo extension needs to be
              # installed for testing most of our projects
              cargo-nextest

              # Commonly used system libraries
              pkg-config
              openssl

              prek
              ;

            # We can consider adding mold/lld/wild for faster linking.
            inherit (self'.packages) famedly-rust-toolchain;
          };

          commands = [
            {
              help = "Run pre-commit hooks on demand";
              name = "filegen-activate";
              command = config.filegen.scripts.activate.outPath;
            }
          ];
        };

        # Install .envrc files that set up the correct devenv into all
        # Rust projects.
        filegen.settings.files = lib.mapAttrsToList (project: _: {
          type = "copy";
          target = "${project}/.envrc";
          source = pkgs.writeText ".envrc" ''
            use flake .#rust
          '';
          clobber = true;
        }) config.famedly.standards.rust.projects;
      }

      (lib.mkIf (lib.hasSuffix "linux" system) {
        devshells.rust.packages = lib.attrValues {
          inherit (pkgs)
            # Used for code coverage, but currently only supported on linux
            cargo-llvm-cov
            ;
        };
      })
    ];
}
