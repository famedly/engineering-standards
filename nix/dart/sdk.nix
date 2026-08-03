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
      packages = {
        famedly-dart-sdk = pkgs.callPackage ./packages/dart-sdk.nix { };
      }
      # Flutter carries prebuilt engine artifacts, which upstream publishes for
      # some of our platforms and not others. Leaving the package out where they
      # do not exist is what lets the toolchain say so in a sentence instead of
      # failing in a fetch.
      // lib.optionalAttrs (lib.elem system [
        "x86_64-linux"
        "aarch64-darwin"
      ]) { famedly-flutter-sdk = pkgs.callPackage ./packages/flutter-sdk.nix { }; };
    };
}
