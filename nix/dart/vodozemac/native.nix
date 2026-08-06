## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

{
  callPackage,
  lib,
  rustPlatform,
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

  # The crate is a pure `cdylib`/`staticlib` with no test targets — `cargo test`
  # would only relink it.
  doCheck = false;

  meta = source.meta // {
    license = lib.licenses.asl20;
  };
}
