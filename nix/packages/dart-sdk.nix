# Dart SDK derivation with a pinned version from nix/sdk-versions.nix.
# Structurally identical to nixpkgs' dart/default.nix, but version and
# hashes come from our central pin so that DevShell and CI use the same binary.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  sdkVersions,
}:

let
  v = sdkVersions.dart;
  system = stdenv.hostPlatform.system;

  platforms = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    x86_64-darwin = "macos-x64";
    aarch64-darwin = "macos-arm64";
  };

  archiveName =
    platforms.${system}
      or (throw "famedly-dart-sdk: unsupported system ${system}; supported: ${lib.concatStringsSep ", " (lib.attrNames platforms)}");

  hash = v.hashes.${system} or (throw "famedly-dart-sdk: no hash for ${system}");
in
stdenv.mkDerivation {
  pname = "famedly-dart-sdk";
  version = v.version;

  src = fetchurl {
    url = "https://storage.googleapis.com/dart-archive/channels/stable/release/${v.version}/sdk/dartsdk-${archiveName}-release.zip";
    inherit hash;
  };

  nativeBuildInputs = [ unzip ];

  installPhase = ''
    runHook preInstall
    rm -f LICENSE README revision
    cp -R . $out
    runHook postInstall
  '';

  # Patch ELF interpreters on Linux so binaries work outside the Nix sandbox.
  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    find $out/bin -type f -executable | while read f; do
      if patchelf --print-interpreter "$f" >/dev/null 2>&1; then
        patchelf \
          --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
          --set-rpath "${lib.makeLibraryPath [ (lib.getLib stdenv.cc.cc) ]}" \
          "$f"
      fi
    done
  '';

  dontStrip = true;

  meta = {
    description = "Dart SDK ${v.version} (Famedly-pinned)";
    homepage = "https://dart.dev";
    mainProgram = "dart";
    platforms = lib.attrNames platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.bsd3;
  };
}
