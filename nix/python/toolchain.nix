## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The Python version floor and the interpreter that provides it, plus the `ruff`
# that formats and lints. Read the interpreter and `ruff` from here instead of
# naming a package, so that the devshell, the formatter, and everything which
# derives a target version agree on them.
{ flake-parts-lib, lib, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, ... }: {
      options.famedly.standards.python = {
        pythonVersion = lib.mkOption {
          description = ''
            The lowest Python version the repository supports, as `major.minor`.

            This is the floor the standards hold code to: `ruff` targets it, so
            it reports use of newer syntax. It is based on Synapse's own floor.
          '';
          type = lib.types.str;
          default = "3.10";
          example = "3.11";
        };

        interpreter = lib.mkOption {
          description = ''
            The Python interpreter the devshell ships.

            Defaults to the interpreter for `pythonVersion`, or, when nixpkgs no
            longer packages that version, the lowest it still packages at or
            above the floor. nixpkgs has dropped 3.10, so a `3.10` floor resolves
            to 3.11 here; `uv` and `hatch` in the devshell can still fetch an
            exact floor interpreter for test runs.
          '';
          type = lib.types.package;

          default =
            let
              parts = lib.splitString "." config.famedly.standards.python.pythonVersion;
              major = lib.head parts;
              minor = lib.toInt (lib.elemAt parts 1);

              # `3.10` → [ "python310" "python311" … ], in ascending order, so the
              # first that nixpkgs packages is the floor itself when it still has
              # it, and the nearest version above it otherwise.
              candidates = map (m: "python${major}${toString m}") (lib.range minor (minor + 20));
              chosen = lib.findFirst (attr: pkgs ? ${attr}) null candidates;
            in
            if chosen != null then
              pkgs.${chosen}
            else
              throw "famedly.standards.python: nixpkgs packages no interpreter at or above ${config.famedly.standards.python.pythonVersion}. See nix/python/toolchain.nix in the engineering standards.";

          defaultText = lib.literalMD "the interpreter for `pythonVersion`, or the nearest nixpkgs packages above it";
        };

        ruff = lib.mkOption {
          description = ''
            The `ruff` that formats and lints Python in this repository. Read
            this instead of naming a package, so that the formatter, the devshell
            and the pre-commit hooks agree on the version, its output and rule
            set change between releases.
          '';
          type = lib.types.package;
          default = pkgs.ruff;
          defaultText = lib.literalExpression "pkgs.ruff";
        };
      };
    }
  );
}
