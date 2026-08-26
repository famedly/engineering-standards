## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ flake-parts-lib, lib, ... }: {
  # These are flake modules. Saying so turns importing them into, say, a NixOS
  # configuration into an error that names the mistake.
  _class = "flake";

  imports = [
    ./dependencies.nix
    ./devshell.nix
    ./formatting.nix
    ./image.nix
    ./image-options.nix
    ./linting.nix
    ./pre-commit-hooks.nix
    ./runtime.nix
    ./toolchain.nix
    ./vodozemac
    ./web

    ./workflows/build-image.nix
    ./workflows/checks.nix
    ./workflows/image.nix
    ./workflows/pre-commit.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      description = ''
        Dart and Flutter projects in the repository that should be equipped
        with our standards.

        This must be a relative path starting with `.`. Simply use `.` if the
        whole project is a Dart project.
      '';
      default = { };

      example = lib.literalExpression ''
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
              This picks the Flutter SDK, enables the lint rules that only
              apply to widgets, and runs dependencies and analysis through
              `flutter` instead of `dart`.
            '';
            type = lib.types.bool;
            default = false;
          };
        }
      );
    };
  });
}
