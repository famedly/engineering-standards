## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.famedly.standards.dart) projects toolchain;

      browser = lib.any (project: project.checks.browser) (lib.attrValues projects);

      # Only where nixpkgs packages one. Elsewhere Flutter falls back to
      # whatever browser the developer has installed.
      chromium = if browser && pkgs.chromium.meta.available then pkgs.chromium else null;
    in
    # The Dart SDK is a large download, so we only pull it in for
    # repositories that actually contain Dart code.
    lib.mkIf (projects != { }) {
      devshells.standards = {
        packages = [ toolchain ] ++ lib.optional (chromium != null) chromium;

        env =
          # This is how `pub` resolves a `sdk: flutter` dependency. nixpkgs
          # only wraps `flutter`, so without this every `dart pub` in a
          # Flutter project stops at "the Flutter SDK is not available".
          lib.optional config.famedly.standards.dart.flutter {
            name = "FLUTTER_ROOT";
            value = "${toolchain}";
          }

          # `flutter test --platform=chrome` has no other way of being told
          # which browser to start, and would otherwise use an unpinned one.
          ++ lib.optional (chromium != null) {
            name = "CHROME_EXECUTABLE";
            value = lib.getExe chromium;
          };
      };
    };
}
