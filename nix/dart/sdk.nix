{ ... }: importingFlake: {
  perSystem = { pkgs, ... }: {
    packages.famedly-dart-sdk = pkgs.callPackage ./packages/dart-sdk.nix { };
  };
}
