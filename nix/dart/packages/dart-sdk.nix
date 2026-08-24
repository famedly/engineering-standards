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
  version = "3.13.1";

  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "macos-arm64";
  };

  hashes = {
    aarch64-darwin = "sha256-NnmElB2NFMZTeJ9veHMS5xXlxUb26fXTDYZhXGkpB6k=";
    aarch64-linux = "sha256-UUHVrGLav88NPdj79cTRQ9AJLvQvrQ8l9s9lh+XPw78=";
    x86_64-linux = "sha256-klHEYG67MUgMRfQwvmn84ml+O4iKCoKLnhbn0jQD1yo=";
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

    # `revision` has to stay: `dart compile exe --target-arch` resolves the
    # matching target SDK from the Dart archive through it, and without it
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
