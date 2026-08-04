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
let
  identity = import ./identity.nix;
in
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
    { lib, ... }: {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }: {
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

                version.enable = lib.mkEnableOption ''
                  telling the application which build it is.

                  `git describe` and the commit reach it as the `version` and
                  `commit` dart-defines, which it reads with
                  `String.fromEnvironment`. Something the user can read off a
                  screen, so that a bug report names a build rather than a day.

                  Costs the job the full history, since a shallow clone carries
                  no tags to describe against
                '';

                sentry.enable = lib.mkEnableOption ''
                  uploading the debug symbols of this build to Sentry.

                  Without them a report from the browser is a stack of minified
                  names and no line numbers, which is to say no stack at all.
                  Turns `version.enable` on, because a symbol file is only ever
                  found again by the release it was filed under.

                  Expects the project's `sentry_dart_plugin` and its `sentry`
                  section in `pubspec.yaml` — which organisation and project to
                  upload to is the project's to say — and the token in the
                  `SENTRY_AUTH_TOKEN` secret
                '';

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

                outputPath = lib.mkOption {
                  description = ''
                    Where `flutter build web` writes the site, relative to the
                    project. Not an option to set: it is the framework's
                    choice, exposed only so `extraSteps` reads the same path
                    the build and the upload step do.
                  '';
                  type = lib.types.str;
                  readOnly = true;
                  default = "build/web";
                };

                extraSteps = lib.mkOption {
                  description = ''
                    Further GitHub Actions steps to run after the web target is
                    built, and before it is uploaded as the artefact that every
                    downstream job — the image, GitHub Pages, review apps —
                    reads from.

                    For steps a project needs that the standards do not know
                    about: stamping a build identifier into the bundle,
                    uploading source maps to an error tracker, or anything else
                    that has to see the built output on disk before it ships.
                    Runs in the same job as the build, working directory
                    unchanged, so a step here reads and writes `outputPath` the
                    same way the build step just did.
                  '';
                  type = lib.types.listOf lib.types.attrs;
                  default = [ ];
                  example = lib.literalExpression ''
                    [
                      {
                        name = "Upload source maps to Sentry";
                        env.SENTRY_AUTH_TOKEN = "\''${{ secrets.SENTRY_AUTH_TOKEN }}";
                        run = "dart run sentry_dart_plugin";
                      }
                    ]
                  '';
                };
              };

              config.web = {
                version.enable = lib.mkDefault config.web.sentry.enable;

                buildCommand = lib.concatStringsSep " " (
                  [
                    "flutter build web"
                    "--release"
                  ]
                  ++ lib.optional config.web.wasm "--wasm"
                  ++ lib.optional (!config.web.webResourcesCdn) "--no-web-resources-cdn"
                  ++ lib.optionals config.web.version.enable [
                    ''--dart-define=version="${identity.version}"''
                    ''--dart-define=commit="${identity.commit}"''
                  ]
                  # The compiler drops the maps unless asked, and the plugin has
                  # nothing to upload without them.
                  ++ lib.optional config.web.sentry.enable "--source-maps"
                  ++ config.web.buildArgs
                );
              };
            }
          )
        );
      };
    }
  );
}
