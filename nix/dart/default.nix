## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ flake-parts-lib, lib, ... }: {
  imports = [
    ./dependencies.nix
    ./devshell.nix
    ./formatting.nix
    ./image.nix
    ./linting.nix
    ./pre-commit-hooks.nix
    ./runtime.nix
    ./toolchain.nix
    ./vodozemac
    ./web

    ./workflows/checks.nix
    ./workflows/image.nix
    ./workflows/pre-commit.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      description = ''
        Dart and Flutter projects in the repository to equip with our
        standards, keyed by a relative path starting with `.`. Use `.` when the
        repository is itself the project.
      '';
      default = { };

      example = ''
        {
          "." = { };
          "./app" = { flutter = true; };
        }
      '';

      type = lib.types.attrsOf (
        lib.types.submodule {
          options.flutter = lib.mkOption {
            description = ''
              Whether this is a Flutter project rather than a plain Dart one.

              What differs is the SDK the toolchain comes from, the lint rules
              that only mean something for widgets, and that dependencies and
              analysis go through `flutter` rather than `dart`.
            '';
            type = lib.types.bool;
            default = false;
          };
        }
      );
    };
  });
}
