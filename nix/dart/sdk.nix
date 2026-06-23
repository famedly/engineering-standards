{ ... }:
importingFlake: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      sdkVersions = import ./sdk-versions.nix;
    in
    {
      # SDK packages — the same binaries are intended to be used by the
      # DevShell and CI workflows so that local and CI builds match.
      #
      # famedly-dart-sdk:    all four supported platforms.
      # famedly-flutter-sdk: not available on aarch64-linux (no upstream binary).
      packages = {
        famedly-dart-sdk = pkgs.callPackage ./packages/dart-sdk.nix { inherit sdkVersions; };
      }
      // lib.optionalAttrs (lib.elem system [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ]) { famedly-flutter-sdk = pkgs.callPackage ./packages/flutter-sdk.nix { inherit sdkVersions; }; };

      apps.updateSdkVersions = {
        type = "app";
        meta.description = "Update nix/dart/sdk-versions.nix to the latest stable Dart and Flutter releases";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "updateSdkVersions";
            runtimeInputs = [
              pkgs.nix
              pkgs.python3
            ];
            text = ''
              exec python3 ${./packages/update-sdk-versions.py} "$@"
            '';
          }
        );
      };
    };
}
