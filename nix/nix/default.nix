## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  flake-parts-lib,
  lib,
  importApply,
  ...
}:
importingFlake: {
  imports = [
    ./formatting.nix
    ./pre-commit-hooks.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { standardsLib, ... }: {
      options.famedly.standards.nix.projects = standardsLib.projectsOption {
        language = "Nix";

        example = ''
          {
            "." = { };
          }
        '';
      };
    }
  );
}
