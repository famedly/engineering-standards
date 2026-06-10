# cargo-udeps requires nightly rustc to work, but our usual toolchain
# is stable.
#
# So we make a custom cargo-udeps binary wrapped with a rustc from the
# nightly channel.
#
# TODO: This should be removed, and replaced with simply the unwrapped
# package whenever the required features land in rust stable.
{
  inputs,

  buildPackages,
  lib,

  runCommand,
  symlinkJoin,

  makeBinaryWrapper,
  cargo-udeps,
}:
let
  rust-bin = inputs.rust-overlay.lib.mkRustBin { } buildPackages;
  rust-nightly = rust-bin.selectLatestNightlyWith (toolchain: toolchain.minimal);

  cargo-udeps-wrapped =
    runCommand "cargo-udeps-wrapped" { nativeBuildInputs = [ makeBinaryWrapper ]; }
      ''
        makeWrapper ${lib.getExe cargo-udeps} $out/bin/cargo-udeps \
          --prefix PATH : ${lib.makeBinPath [ rust-nightly ]}
      '';
in
symlinkJoin {
  name = "cargo-udeps";

  paths = [
    cargo-udeps-wrapped
    cargo-udeps
  ];
}
