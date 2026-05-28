{ inputs, ... }:
importingFlake: {
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
          packages =
            (lib.attrValues {
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
                ;

              # We can consider adding mold/lld/wild for faster linking.
              inherit (self'.packages) famedly-rust-toolchain;

              # To check dependencies are actually used
              cargo-udeps = pkgs.callPackage ./packages/cargo-udeps.nix { inherit inputs; };
            })

            # TODO: Find a nice way to inherit all settings from the
            # general devshell, not just package.
            ++ config.devshells.general.packages;
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
