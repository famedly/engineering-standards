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
        devshells.rust =
          { extraModulesPath, ... }:
          {
            imports = [
              "${extraModulesPath}/language/c.nix"
              "${extraModulesPath}/language/rust.nix"
            ];

            language = {
              c = {
                libraries = [ pkgs.openssl ];
                includes = [ pkgs.openssl ];
              };

              rust.enableDefaultToolchain = false;
            };

            packages = lib.attrValues {
              inherit (pkgs)
                # We have some projects that use cargo workspaces, this tool makes
                # matching up dependencies between subcrates easier.
                cargo-autoinherit

                # We use nextest for testing, this cargo extension needs to be
                # installed for testing most of our projects
                cargo-nextest
                ;

              inherit (self'.packages) famedly-rust-toolchain;

              # To check dependencies are actually used
              cargo-udeps = pkgs.callPackage ./packages/cargo-udeps.nix { inherit inputs; };
            };

            env = [
              {
                name = "RUST_SRC_PATH";
                value = "${self'.packages.famedly-rust-toolchain}/lib/rustlib/src/rust/library";
              }
            ];

            # TODO: Find a better way to inherit devshell
            # configurations.
            commands = lib.filter (command: command.name != "menu") config.devshells.standards.commands;
          };
      }

      (lib.mkIf (lib.hasSuffix "linux" system) {
        devshells.rust.packages = [
          # Used for code coverage, but currently only supported on linux
          pkgs.cargo-llvm-cov
        ];
      })
    ];
}
