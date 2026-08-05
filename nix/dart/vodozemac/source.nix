# The source the bindings are built from, named once for both targets: the
# native library and the WebAssembly module are the same crate compiled twice,
# and a version that drifted between them fails at the first call and not
# before.
{ fetchFromGitHub }:

let
  # Keep in sync with the `vodozemac` constraint in consumers' `pubspec.yaml`,
  # which a pre-commit hook checks. The tags follow the Flutter plugin.
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "famedly";
    repo = "dart-vodozemac";
    tag = version;
    hash = "sha256-H3g0is/+Cf3xBqqxw6qCjZSv5ZjftNSQP4hdwwEsOrs=";
  };
in
{
  inherit version src;

  # The repository is a Flutter plugin; only the crate is interesting to us.
  sourceRoot = "${src.name}/rust";

  # One lockfile, so one vendor for both targets.
  cargoHash = "sha256-eKKrcroV2yl/FV2WmgZWFPO5MPAGz0xCvpr0fgIuGZ4=";

  meta = {
    description = "Dart bindings for the vodozemac Matrix cryptography library";
    homepage = "https://github.com/famedly/dart-vodozemac";
  };
}
