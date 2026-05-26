{ inputs, ... }:
importingFlake: {
  imports = [ inputs.devenv.flakeModule ];

  perSystem =
    {
      lib,
      self',
      pkgs,
      system,
      ...
    }:
    lib.mkMerge [
      {
        devenv.shells.rust = {
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
              ;
          };

          languages.rust = {
            enable = true;
            toolchainPackage = self'.packages.famedly-rust-toolchain;

            # We can consider enabling mold/lld/wild for faster linking.
          };
        };
      }

      (lib.mkIf (lib.hasSuffix "linux" system) {
        devenv.shells.rust.packages = lib.attrValues {
          inherit (pkgs)
            # Used for code coverage, but currently only supported on linux
            cargo-llvm-cov
            ;
        };
      })
    ];
}
