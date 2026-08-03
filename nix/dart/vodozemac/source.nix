# The source the bindings are built from, named once for both targets.
#
# The native library and the WebAssembly module are the same crate compiled
# twice, and the Dart package that calls them is generated from this very
# revision. A version that drifted between the two would leave an application
# talking to bindings it was not generated against — which nothing catches
# until a call is made.
{ fetchFromGitHub }:

let
  # Keep in sync with the `vodozemac` constraint in consumers' `pubspec.yaml`:
  # the Dart package and these bindings are released together. The repository's
  # tags follow the Flutter plugin's version, which for this release is the same
  # as the Dart package's.
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

  # One lockfile, so one vendor: which dependencies a target actually links is
  # decided when it is built, not when they are resolved.
  cargoHash = "sha256-eKKrcroV2yl/FV2WmgZWFPO5MPAGz0xCvpr0fgIuGZ4=";

  meta = {
    description = "Dart bindings for the vodozemac Matrix cryptography library";
    homepage = "https://github.com/famedly/dart-vodozemac";
  };
}
