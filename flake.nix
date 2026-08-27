## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
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

        perSystem = { self', pkgs, ... }: {
          packages.docs =
            (pkgs.nixosOptionsDoc {
              options =
                let
                  getModuleOptions =
                    evaluatedModule:
                    ((evaluatedModule.type.getSubOptions [ "perSystem" ]).perSystem.type.getSubOptions [ ]);
                  inherit (inputs.flake-parts.lib) evalFlakeModule;
                in
                {
                  filegen =
                    let
                      evaluatedModule = evalFlakeModule { inherit inputs; } flakeModules.filegen;
                      filegenOptions = getModuleOptions evaluatedModule;
                    in
                    filegenOptions.filegen;
                };
            }).optionsCommonMark;
          filegen.settings.files = [
            {
              type = "copy";
              target = "options.md";
              source = self'.packages.docs;
            }
          ];
        };

        flake.flakeModules = flakeModules // {
          inherit default;
        };

        imports = [
          default

          # This repository's own checks, which downstream flakes do not get.
          ./nix/dart/tests
        ];
      }
    );
}
