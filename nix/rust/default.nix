## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  flake-parts-lib,
  lib,
  importApply,
  ...
}@args:
importingFlake: {
  imports = [
    (importApply ./devshell.nix args)
    (importApply ./formatting.nix args)
    (importApply ./toolchain.nix args)
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { standardsLib, ... }: {
      options.famedly.standards.rust.projects = standardsLib.projectsOption {
        language = "Rust";

        example = ''
          {
            "." = { };
          }
        '';
      };
    }
  );
}
