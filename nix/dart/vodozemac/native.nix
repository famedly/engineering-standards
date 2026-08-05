{
  callPackage,
  fixDarwinDylibNames,
  lib,
  rustPlatform,
  stdenv,
}:

let
  source = callPackage ./source.nix { };
in
rustPlatform.buildRustPackage {
  pname = "famedly-vodozemac";

  inherit (source)
    version
    src
    sourceRoot
    cargoHash
    ;

  # Otherwise the linker names the build directory as the library's own
  # location, and that directory stops existing the moment the build finishes.
  nativeBuildInputs = lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames;

  # Darwin has no sandbox to remap the build directory to a constant, so the
  # random path reaches the debug info, the panic locations and the hashes LLVM
  # derives from a module's path — and two builds are never the same bytes.
  # Rewriting the prefix makes the static library reproducible; the shared one
  # keeps a UUID the linker derives from the rest.
  preBuild = ''
    export RUSTFLAGS="''${RUSTFLAGS-} --remap-path-prefix=$NIX_BUILD_TOP=/build"
  '';

  # The crate is a pure `cdylib`/`staticlib` with no test targets — `cargo test`
  # would only relink it.
  doCheck = false;

  meta = source.meta // {
    license = lib.licenses.asl20;
  };
}
