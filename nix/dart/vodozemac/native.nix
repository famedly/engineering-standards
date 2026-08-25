## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

{
  fixDarwinDylibNames,
  lib,
  rustPlatform,
  source,
  stdenv,
}:

rustPlatform.buildRustPackage {
  pname = "famedly-vodozemac";

  inherit (source)
    version
    src
    sourceRoot
    cargoHash
    ;

  # Otherwise the linker names the build directory as the library's location.
  nativeBuildInputs = lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames;

  # Darwin has no sandbox to give the build a constant directory, so the
  # random path reaches the debug info, the panic locations and LLVM's module
  # hashes. Rewriting the prefix makes the static library reproducible, while
  # the shared one keeps a UUID the linker derives from the rest.
  preBuild = ''
    export RUSTFLAGS="''${RUSTFLAGS-} --remap-path-prefix=$NIX_BUILD_TOP=/build"
  '';

  # This is a pure `cdylib`/`staticlib`, `cargo test` would only relink it.
  doCheck = false;

  meta = source.meta // {
    license = lib.licenses.asl20;
  };
}
