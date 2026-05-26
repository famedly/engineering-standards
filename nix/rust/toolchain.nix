{ inputs, ... }:
importingFlake: {
  perSystem =
    { lib, pkgs, ... }:
    let
      rust-bin = inputs.rust-overlay.lib.mkRustBin { } pkgs.buildPackages;
    in
    {
      # TODO: Ideally we'd specify a rust-toolchain.toml file, but
      # rustup doesn't currently support our toolchain because we want
      # to use nightly specifically for `rustfmt`. See this issue for
      # a potential future resolution:
      #
      # https://github.com/rust-lang/rustup/issues/4636
      #
      # TODO: enumerate the things that make it so we can't just use
      # stable `rustfmt`.
      packages.famedly-rust-toolchain = pkgs.buildEnv {
        inherit (rust-bin.stable.latest.default) name;

        # We're intentionally colliding rustfmt paths to override the
        # defaults.
        ignoreCollisions = true;

        paths =
          let
            # The toolchain whose rustfmt we want to use.
            rustfmtToolchain = rust-bin.selectLatestNightlyWith (
              toolchain: toolchain.default.override { extensions = [ "rustfmt" ]; }
            );

            # We want *only* the rustfmt binaries. This trick doesn't
            # really work for other components of the rust toolchain,
            # but specifically rustfmt is quite self-contained.
            rustfmtNightly = pkgs.runCommand rustfmtToolchain.name { } ''
              mkdir -p $out/bin
              cp ${rustfmtToolchain}/bin/{cargo-fmt,rustfmt} $out/bin
            '';
          in
          [
            rustfmtNightly
            rust-bin.stable.latest.default
          ];
      };
    };
}
