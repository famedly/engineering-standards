{
  description = "Famedly Engineering Standards — Nix-first standards distribution";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-25.11/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        self,
        lib,
        flake-parts-lib,
        moduleWithSystem,
        ...
      }@args:
      let
        inherit (flake-parts-lib) importApply;

        flakeModules = rec {
          filegen = ./nix/modules/filegen.nix;
          prek-pre-commit = importApply ./nix/modules/prek-pre-commit.nix { inherit filegen; };
        };

        default = importApply ./nix (args // { inherit importApply flakeModules; });
      in
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        flake.flakeModules = flakeModules // {
          inherit default;
        };

        imports = [ default ];
      }
    );
}
