# The source the bindings are built from, named once for both targets: the
# native library and the WebAssembly module are the same crate compiled twice,
# and a version that drifted between them fails at the first call and not
# before.
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

    # The repository is a Flutter plugin; its tags follow that plugin's version,
    # which for the releases we build is the Dart package's as well.
    tag = version;

    inherit hash;
  };
in
{
  inherit version src cargoHash;

  # The repository is a Flutter plugin; only the crate is interesting to us.
  sourceRoot = "${src.name}/rust";

  meta = {
    description = "Dart bindings for the vodozemac Matrix cryptography library";
    homepage = "https://github.com/famedly/dart-vodozemac";
  };
}
