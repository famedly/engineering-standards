## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: importingFlake: {
  config.perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.famedly.standards.dart) projects toolchain;

      browser = lib.any (project: project.checks.browser) (lib.attrValues projects);

      # Only where nixpkgs has one. On a machine it does not build for, Flutter
      # falls back to looking for a browser the developer installed themselves —
      # which is the state every one of these repositories was in before.
      chromium = if browser && pkgs.chromium.meta.available then pkgs.chromium else null;
    in
    # The Dart SDK is a hefty download, so only pull it in for repositories
    # that actually contain Dart code.
    lib.mkIf (projects != { }) {
      devshells.standards = {
        packages = [ toolchain ] ++ lib.optional (chromium != null) chromium;

        env =
          # `pub` resolves a `sdk: flutter` dependency — `flutter_test`, for one
          # — by reading this. The `dart` beside `flutter` in the SDK is the bare
          # binary, and nixpkgs wraps only `flutter`, so without this every `dart
          # pub` in a Flutter project stops at "the Flutter SDK is not
          # available". Flutter's own `bin/dart` script sets exactly this.
          lib.optional config.famedly.standards.dart.flutter {
            name = "FLUTTER_ROOT";
            value = "${toolchain}";
          }

          # `flutter test --platform=chrome` starts whatever this points at, and
          # has no other way of being told. Without it the browser tests run
          # against whichever browser the machine happens to carry, which on a
          # CI runner is a browser nothing in this repository pins.
          ++ lib.optional (chromium != null) {
            name = "CHROME_EXECUTABLE";
            value = lib.getExe chromium;
          };
      };
    };
}
