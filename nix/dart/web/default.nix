## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# A Flutter project's web target: built once, then handed to every destination
# that is enabled for it — a container image, GitHub Pages, a review app.
#
# Keyed on the project rather than on the site it produces, so that the project
# path, whether its dependencies are private, and how a Flutter web application
# is built are each stated once. The destinations are jobs of one workflow
# because artefacts are shared within a run and not across them, which is what
# makes all three ship the very bytes that were built and tested.
{ flake-parts-lib, ... }:
{
  imports = [
    ./assets.nix
    ./image.nix

    ./workflows/build.nix
    ./workflows/github-pages.nix
    ./workflows/image.nix
    ./workflows/review-app.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              options.web = {
                enable = lib.mkEnableOption ''
                  building this project's web target and shipping it

                  Only meaningful for a Flutter project: there is no web build
                  without the framework
                '';

                wasm = lib.mkOption {
                  description = ''
                    Whether to compile to WebAssembly.

                    On, because it is where Flutter's web support is going and
                    what it renders best with. It does place a demand on
                    whatever serves the result — a browser refuses to
                    instantiate a module that is not typed `application/wasm` —
                    which is why the image asserts that rather than assuming it.
                  '';
                  type = lib.types.bool;
                  default = true;
                };

                webResourcesCdn = lib.mkOption {
                  description = ''
                    Whether to fetch canvaskit and the icon fonts from Google's
                    CDN at runtime.

                    Off, so the application carries everything it needs. A
                    frontend for a hospital network should not have to reach a
                    third party to render, and an air-gapped deployment cannot.
                  '';
                  type = lib.types.bool;
                  default = false;
                };

                buildArgs = lib.mkOption {
                  description = ''
                    Further arguments for `flutter build web`.
                  '';
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  example = [ "--dart-define=FLAVOR=production" ];
                };

                buildCommand = lib.mkOption {
                  description = ''
                    The command CI runs to build the web target, derived from
                    the options above.

                    Exposed so that it can be read out of the flake when a
                    build has to be reproduced by hand.
                  '';
                  type = lib.types.str;
                  readOnly = true;
                };
              };

              config.web.buildCommand = lib.concatStringsSep " " (
                [
                  "flutter build web"
                  "--release"
                ]
                ++ lib.optional config.web.wasm "--wasm"
                ++ lib.optional (!config.web.webResourcesCdn) "--no-web-resources-cdn"
                ++ config.web.buildArgs
              );
            }
          )
        );
      };
    }
  );
}
