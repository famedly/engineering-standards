{
  fetchFromGitHub,
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "famedly-vodozemac";

  # Keep in sync with the `vodozemac` constraint in consumers' `pubspec.yaml`:
  # the Dart package and these bindings are released together.
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "famedly";
    repo = "dart-vodozemac";
    tag = finalAttrs.version;
    hash = "sha256-H3g0is/+Cf3xBqqxw6qCjZSv5ZjftNSQP4hdwwEsOrs=";
  };

  # The repository is a Flutter plugin; only the crate is interesting to us.
  sourceRoot = "${finalAttrs.src.name}/rust";

  cargoHash = "sha256-eKKrcroV2yl/FV2WmgZWFPO5MPAGz0xCvpr0fgIuGZ4=";

  # The crate is a pure `cdylib`/`staticlib` with no test targets — `cargo test`
  # would only relink it.
  doCheck = false;

  meta = {
    description = "Dart bindings for the vodozemac Matrix cryptography library";
    homepage = "https://github.com/famedly/dart-vodozemac";
    license = lib.licenses.asl20;
  };
})
