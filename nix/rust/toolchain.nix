## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
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
            # We currently use rustfmt from nightly for these features:
            #
            # - [comment_width](https://github.com/rust-lang/rustfmt/issues/3349)
            # - [doc_comment_code_block_width](https://github.com/rust-lang/rustfmt/issues/5359)
            # - [format_code_in_doc_comments](https://github.com/rust-lang/rustfmt/issues/3348)
            # - [group_imports](https://github.com/rust-lang/rustfmt/issues/5083)
            # - [imports_granularity](https://github.com/rust-lang/rustfmt/issues/4991)
            # - [wrap_comments](https://github.com/rust-lang/rustfmt/issues/3347)
            #
            # fenix fetches *only* the `rustfmt-preview` dist component
            # (bin/{rustfmt,cargo-fmt}) alongside the `rustc` package
            # it depends on for its runtime libraries (librustc_driver,
            # libLLVM). fenix patches the rpath on Linux and wraps
            # rustfmt with `DYLD_LIBRARY_PATH` on Darwin, so the
            # binaries keep working on both platforms — no full
            # nightly toolchain is needed alongside the stable one
            # below.
            rustfmtNightly = inputs.fenix.packages.${pkgs.system}.default.rustfmt-preview;
          in
          [
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

      # For CI, you do not want to use the `famedly-rust-toolchain`, since
      # it contains a lot of rust documentation and other stuff which isn't
      # strictly necessary for building your project, and which inflates
      # the size of your closure.
      #
      # Having too large a project closure results in your CI slowing down.
      packages.famedly-rust-build-toolchain = rust-bin.stable.latest.minimal;

    };
}
