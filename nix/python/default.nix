## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ flake-parts-lib, lib, ... }: importingFlake: {
  # These are flake modules. Saying so turns importing them into, say, a NixOS
  # configuration into an error that names the mistake.
  _class = "flake";

  imports = [
    ./toolchain.nix
    ./devshell.nix
    ./formatting.nix
    ./linting.nix
    ./pre-commit-hooks.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.python.projects = lib.mkOption {
      description = ''
        Python projects in the repository that should be equipped with our
        standards.

        This must be a relative path starting with `.`. Simply use `.` if the
        whole project is a Python project.
      '';
      default = { };

      example = ''
        {
          "." = { };
        }
      '';

      type = lib.types.attrsOf (lib.types.submodule { });
    };
  });
}
