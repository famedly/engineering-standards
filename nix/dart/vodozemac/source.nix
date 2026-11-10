## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# We name this once for both targets, since the native library and the
# WebAssembly module are the same crate compiled twice and a version that
# drifted between them would fail at the first call and not before.
{
  fetchFromGitHub,
  lib,
  version,
  hash,
  cargoHash,
}:

let
  src = fetchFromGitHub {
    owner = "famedly";
    repo = "dart-vodozemac";

    # The plugin's tags, which for the releases we build are the package's.
    tag = version;

    inherit hash;
  };
in
{
  inherit version src cargoHash;

  # We only care about the crate.
  sourceRoot = "${src.name}/rust";

  meta = {
    description = "Dart bindings for the vodozemac Matrix cryptography library";
    homepage = "https://github.com/famedly/dart-vodozemac";
    license = lib.licenses.asl20;
  };
}
