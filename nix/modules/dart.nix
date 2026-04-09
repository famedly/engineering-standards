# Dart/Flutter specific standards module.
#
# Provides:
# - Dev shell with Dart/Flutter SDK
# - Auto-enables the Dart CI workflow (workflows.dartCi) so that
#   dart analyze, dart format, import sorting, etc. actually run in CI.
#
# Dart/Flutter checks cannot run inside the Nix sandbox (they need
# `pub get` which requires network access). The real quality checks
# are performed by the reusable dart-ci.yml GitHub Actions workflow.

{ flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.dart;
    in
    {
      options.famedly.standards.dart = {
        enable = lib.mkEnableOption "Dart/Flutter standards";

        flutter = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Flutter-specific tooling (flutter SDK instead of dart).";
        };

        dartSdk = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = ''
            Override the Dart/Flutter SDK package.
            Defaults to packages.famedly-dart-sdk or packages.famedly-flutter-sdk
            (from nix/sdk-versions.nix). Set to pkgs.dart or pkgs.flutter to use
            the nixpkgs version instead.
          '';
        };
      };

      config =
        let
          sdk =
            if cfg.dartSdk != null then
              cfg.dartSdk
            else if cfg.flutter then
              config.packages.famedly-flutter-sdk or pkgs.flutter
            else
              config.packages.famedly-dart-sdk;

          dartShell = pkgs.mkShell {
            name = "dart-dev";
            packages = [ sdk ];
          };
        in
        lib.mkIf cfg.enable {
          devShells.dart = dartShell;

          famedly.github.workflows.dart-ci.enable = lib.mkDefault true;
        };
    }
  );
}
