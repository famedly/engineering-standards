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

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { standardsLib, ... }: {
      options.famedly.standards.dart.projects = standardsLib.projectsOption {
        language = "Dart and Flutter";
        kind = "Dart";

        example = lib.literalExpression ''
          {
            "." = { };
            "./app" = { flutter = true; };
          }
        '';

        submodule = {
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
        };
      };
    }
  );
}
