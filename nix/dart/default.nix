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
    (importApply ./linting.nix args)
    (importApply ./sdk.nix args)
    (importApply ./vodozemac args)

    ./dependencies.nix
    ./image.nix
    ./pre-commit-hooks.nix
    ./runtime.nix
    ./toolchain.nix
    ./web

    ./workflows/checks.nix
    ./workflows/image.nix
    ./workflows/pre-commit.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      description = ''
        Dart and Flutter projects in the repository that should be equipped with
        our standards.

        This must be a relative path starting with `.`. Simply use `.` if the
        whole project is a Dart project.
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

              Flutter is Dart plus a framework, so the two share nearly
              everything the standards do. What differs is the SDK the toolchain
              comes from, the lint rules that only mean something for widgets,
              and that dependencies and analysis go through `flutter` rather
              than `dart`.
            '';
            type = lib.types.bool;
            default = false;
          };
        }
      );
    };
  });
}
