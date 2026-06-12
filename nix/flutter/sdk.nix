{ ... }:
importingFlake: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      packages = lib.optionalAttrs (lib.elem system [
        "x86_64-linux"
        "aarch64-darwin"
      ]) { famedly-flutter-sdk = pkgs.callPackage ./packages/flutter-sdk.nix { }; };
    };
}
