## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  fetchurl,
  lib,
  stdenv,
  unzip,
}:

let
  # We read the Dart version out of the data that packages Flutter, rather
  # than pinning it a second time. A Flutter project runs the `dart` from its
  # own SDK anyway, so following the same release keeps a repository that
  # holds both from formatting its code two different ways.
  data = lib.importJSON ./flutter-sdk-data.json;

  version = data.dartVersion;
  hashes = data.dartHash;

  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "macos-arm64";
  };

  archiveName =
    platforms.${stdenv.hostPlatform.system}
      or (throw "famedly-dart-sdk: unsupported system ${stdenv.hostPlatform.system}; supported: ${lib.concatStringsSep ", " (lib.attrNames platforms)}");
in
stdenv.mkDerivation {
  pname = "famedly-dart-sdk";
  inherit version;

  src = fetchurl {
    url = "https://storage.googleapis.com/dart-archive/channels/stable/release/${version}/sdk/dartsdk-${archiveName}-release.zip";
    hash = hashes.${stdenv.hostPlatform.system};
  };

  nativeBuildInputs = [ unzip ];

  installPhase = ''
    runHook preInstall

    # We have to keep `revision`, since `dart compile exe --target-arch` uses
    # it to resolve the matching target SDK from the Dart archive. Without it
    # cross-compiling fails with 'Channel "stable" requires valid revision'.
    rm -f LICENSE README
    cp -R . $out
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    find $out/bin -type f -executable | while read f; do
      if patchelf --print-interpreter "$f" >/dev/null 2>&1; then
        patchelf \
          --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
          --set-rpath "${lib.makeLibraryPath [ (lib.getLib stdenv.cc.cc) ]}" \
          "$f"
      fi
    done
  ''
  + ''
    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Dart SDK ${version} (Famedly-pinned)";
    homepage = "https://dart.dev";
    changelog = "https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md";
    mainProgram = "dart";
    platforms = lib.attrNames platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.bsd3;
    maintainers = [
      {
        name = "Famedly GmbH";
        email = "info@famedly.com";
        github = "famedly";
        githubId = 46558835;
      }
    ];
  };
}
