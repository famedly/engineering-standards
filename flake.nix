{
  description = "Famedly Engineering Standards — Nix-first standards distribution";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    github-actions-nix = {
      url = "github:synapdeck/github-actions-nix";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wrappers = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt = {
      url = "github:numtide/treefmt-nix";
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
          prek-pre-commit = importApply ./nix/modules/prek-pre-commit.nix {
            inherit filegen;
            inherit (inputs) wrappers;
          };
        };

        default = importApply ./nix (args // { inherit importApply flakeModules; });
      in
      {
        systems = self.lib.famedlySystems;

        flake.flakeModules = flakeModules // {
          inherit default;
        };

        imports = [ default ];

        # The toolchain every repository pinning these standards resolves
        # against, built here so that none of them has to.
        #
        # Only for the system CI runs on. Laptops are `aarch64-darwin`, and
        # building for them costs ten times the minutes, but the SDKs are
        # archives someone else already built — handing a laptop the same three
        # gigabytes from a different host saves it nothing. What is left is
        # vodozemac, and that is half a minute.
        famedly.standards.ci.binaryCache.populate.x86_64-linux = [
          ".#devShells.x86_64-linux.standards"
          ".#packages.x86_64-linux.famedly-dart-sdk"
          ".#packages.x86_64-linux.famedly-flutter-sdk"
          ".#packages.x86_64-linux.famedly-rust-toolchain"
          ".#packages.x86_64-linux.famedly-vodozemac"
        ];
      }
    );
}
