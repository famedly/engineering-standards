{ inputs, ... }: importingFlake: {
  perSystem =
    { lib, pkgs, ... }:
    let
      rust-bin = inputs.rust-overlay.lib.mkRustBin { } pkgs.buildPackages;
    in
    {
      # TODO: Ideally we'd specify a rust-toolchain.toml file, but
      # rustup doesn't currently support mixing components from
      # different toolchain versions. See this issue for a potential
      # future resolution:
      #
      # https://github.com/rust-lang/rustup/issues/4636
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
            # We currently use rustfmt nightly for these features:
            #
            # - [comment_width](https://github.com/rust-lang/rustfmt/issues/3349)
            # - [doc_comment_code_block_width](https://github.com/rust-lang/rustfmt/issues/5359)
            # - [format_code_in_doc_comments](https://github.com/rust-lang/rustfmt/issues/3348)
            # - [group_imports](https://github.com/rust-lang/rustfmt/issues/5083)
            # - [imports_granularity](https://github.com/rust-lang/rustfmt/issues/4991)
            # - [wrap_comments](https://github.com/rust-lang/rustfmt/issues/3347)
            rustfmtNightly
            (rust-bin.stable.latest.default.override {
              extensions = [
                "rust-src"
                "rust-analyzer"
                "llvm-tools"
              ];
            })
          ];

        inherit (rust-bin.stable.latest.default) passthru;
      };
    };
}
