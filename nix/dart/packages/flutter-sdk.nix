# Flutter SDK derivation with a pinned version from nix/dart/sdk-versions.nix.
# Flutter stable does not publish Linux arm64 binaries — aarch64-linux is
# therefore not supported.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  bash,
  curl,
  git,
  unzip,
  xz,
  fontconfig,
  gtk3,
  libGL,
  libepoxy,
  pango,
  glib,
  sdkVersions,
}:

let
  v = sdkVersions.flutter;
  inherit (stdenv.hostPlatform) system;

  archives = {
    x86_64-linux = {
      url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${v.version}-stable.tar.xz";
      hash = v.hashes.x86_64-linux;
    };
    x86_64-darwin = {
      url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_${v.version}-stable.zip";
      hash = v.hashes.x86_64-darwin;
    };
    aarch64-darwin = {
      url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_${v.version}-stable.zip";
      hash = v.hashes.aarch64-darwin;
    };
  };

  archive =
    archives.${system}
      or (throw "famedly-flutter-sdk: unsupported system ${system}; supported: ${lib.concatStringsSep ", " (lib.attrNames archives)}");
in
stdenv.mkDerivation {
  pname = "famedly-flutter-sdk";
  inherit (v) version;

  src = fetchurl { inherit (archive) url hash; };

  nativeBuildInputs = [
    unzip
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    xz
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    bash
    curl
    git
    fontconfig
    gtk3
    libGL
    libepoxy
    pango
    glib
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R . $out/flutter
    # Symlink binaries for PATH
    mkdir -p $out/bin
    ln -s $out/flutter/bin/flutter $out/bin/flutter
    ln -s $out/flutter/bin/dart $out/bin/dart
    runHook postInstall
  '';

  dontStrip = true;
  dontBuild = true;

  meta = {
    description = "Flutter SDK ${v.version} (Famedly-pinned)";
    homepage = "https://flutter.dev";
    changelog = "https://github.com/flutter/flutter/blob/main/CHANGELOG.md";
    mainProgram = "flutter";
    platforms = lib.attrNames archives;
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
