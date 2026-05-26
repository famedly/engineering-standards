{
  description = "Famedly Engineering Standards — Nix-first standards distribution";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-25.11/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";

    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
      # TODO: Dedup inputs
    };

    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
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
        flakeModules.default = importApply ./nix (args // { inherit importApply; });
      in
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        imports = [ flakeModules.default ];

        flake = lib.mkMerge [ { inherit flakeModules; } ];
      }
    );
}
