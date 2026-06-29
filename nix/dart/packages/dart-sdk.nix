{
  fetchurl,
  lib,
  stdenv,
  unzip,
}:

let
  version = "3.12.2";

  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "macos-arm64";
  };

  hashes = {
    aarch64-darwin = "sha256-zYdTko53trZlvXDc4OZLTsbS4v3hQdZAm7cWyKwfHAo=";
    aarch64-linux = "sha256-+CyD7OfRaAR1UN/UpmTkBxrHxIi923LcQxAsItfgtRg=";
    x86_64-linux = "sha256-KOR7RM8HXzZ3EEbAaLsNF0IBz5x2CHRK7RzCMgQpnC0=";
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

  nativeBuildInputs = [
    unzip
  ];

  installPhase = ''
    runHook preInstall

    rm -f LICENSE README revision
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
