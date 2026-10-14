## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ flake-parts-lib, lib, ... }:
_importingFlake:
let
  ruffType =
    pkgs:
    lib.types.submodule {
      freeformType = (pkgs.formats.toml { }).type;
      options.disabledRules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "TRY003" ];
        description = ''
          Shared ignored Ruff rules to enable for this project.
        '';
      };
    };
in
{
  imports = [
    ./formatting.nix
    ./linting.nix
    ./pre-commit-hooks.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { pkgs, ... }: {
      options.famedly.standards.python = {
        projects = lib.mkOption {
          description = ''
            Python projects in the repository that should be equipped with our
            standards.

            The key is the path to the project, relative to the repository root, and
            must start with `.`. Use `.` if the whole repository is a single Python
            project.
          '';
          default = { };
          example = {
            "." = { };
          };

          type = lib.types.attrsOf (
            lib.types.submodule {
              options.ruff = lib.mkOption {
                type = ruffType pkgs;
                default = { };
                description = ''
                  Extra Ruff configuration for this project, merged into the
                  generated `ruff.toml` on top of the shared standards. Use
                  `disabledRules` to remove individual entries from the shared
                  ignore list.
                '';
                example = {
                  line-length = 100;
                  disabledRules = [ "TRY003" ];
                  lint.extend-select = [
                    "I"
                    "D"
                  ];
                };
              };
            }
          );
        };
      };
    }
  );
}
