# Rust GitHub App — built & tested via `nix flake check` (dogfooding the Nix-only CI pattern).

{ pkgs, lib }:

pkgs.rustPlatform.buildRustPackage {
  pname = "engineering-standards-app";
  version = (lib.importTOML ../app/Cargo.toml).package.version;

  src = ../app;

  cargoLock.lockFile = ../app/Cargo.lock;

  nativeBuildInputs = with pkgs; [
    pkg-config
    clippy
    gitMinimal # vergen build.rs
  ];
  buildInputs = with pkgs; [ openssl ];

  doCheck = true;

  checkPhase = ''
    runHook preCheck
    cargo clippy --all-targets --locked -- -D warnings
    cargo test --workspace --locked
    runHook postCheck
  '';

  meta = {
    description = "Famedly engineering-standards GitHub App";
    license = lib.licenses.mit;
  };
}
