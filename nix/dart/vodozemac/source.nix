## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Named once for both targets: the native library and the WebAssembly module
# are the same crate compiled twice, and a version that drifted between them
# fails at the first call and not before.
{
  fetchFromGitHub,
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

  # Only the crate is interesting to us.
  sourceRoot = "${src.name}/rust";

  meta = {
    description = "Dart bindings for the vodozemac Matrix cryptography library";
    homepage = "https://github.com/famedly/dart-vodozemac";
  };
}
