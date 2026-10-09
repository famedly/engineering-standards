## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ flake-parts-lib, lib, ... }: importingFlake: {
  imports = [
    ./formatting.nix
    ./linting.nix
    ./pre-commit-hooks.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.python.projects = lib.mkOption {
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
            description = ''
              Extra Ruff configuration for this project, merged into the
              generated `ruff.toml` on top of the shared standards.

              The standards own `ruff.toml` and overwrite it, so project-specific
              rules belong here rather than in that file. Prefer Ruff's `extend-*`
              keys (`extend-select`, `extend-ignore`, `extend-per-file-ignores`)
              so the shared lists are extended rather than replaced.
            '';
            type = lib.types.attrsOf lib.types.anything;
            default = { };
            example = {
              line-length = 100;
              lint.extend-ignore = [ "E501" ];
            };
          };
        }
      );
    };
  });
}
