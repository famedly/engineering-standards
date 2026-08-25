## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# A Flutter project's web target: built once, then handed to every destination
# enabled for it — a container image, GitHub Pages, a review app.
#
# The destinations are jobs of one workflow because artefacts are shared within
# a run and not across them, which is what makes all three ship the very bytes
# that were built and tested.
{
  flake-parts-lib,
  lib,
  standardsLib,
  ...
}:
{
  imports = [
    ./assets.nix
    ./image.nix

    ./workflows/build.nix
    ./workflows/github-pages.nix
    ./workflows/image.nix
    ./workflows/review-app.nix

    (import ../project-options.nix { inherit lib flake-parts-lib; } (
      { config, name, ... }: {
        options.web = {
          enable = lib.mkEnableOption ''
            building this project's web target and shipping it

            Only meaningful for a Flutter project: there is no web build without
            the framework
          '';

          wasm = lib.mkOption {
            description = ''
              Whether to compile to WebAssembly.

              On: it is where Flutter's web support is going and what it renders
              best with. It does demand something of whatever serves the result,
              which is why the image asserts the content type rather than
              assuming it.
            '';
            type = lib.types.bool;
            default = true;
          };

          webResourcesCdn = lib.mkOption {
            description = ''
              Whether to fetch canvaskit and the icon fonts from Google's CDN at
              runtime.

              Off, so the application carries everything it needs: an air-gapped
              deployment cannot reach a third party to render.
            '';
            type = lib.types.bool;
            default = false;
          };

          version.enable = lib.mkEnableOption ''
            telling the application which build it is.

            `git describe` and the commit reach it as the `version` and `commit`
            dart-defines, read with `String.fromEnvironment`, so a bug report
            can name a build rather than a day.

            Costs the job the full history: a shallow clone carries no tags to
            describe against
          '';

          sentry.enable = lib.mkEnableOption ''
            uploading the debug symbols of this build to Sentry.

            Without them a report from the browser is minified names and no line
            numbers. Turns `version.enable` on: a symbol file is found again by
            the release it was filed under.

            Expects the project's `sentry_dart_plugin` and its `sentry` section
            in `pubspec.yaml`, and the token in the `SENTRY_AUTH_TOKEN` secret
          '';

          buildArgs = lib.mkOption {
            description = "Further arguments for `flutter build web`.";
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "--dart-define=FLAVOR=production" ];
          };

          buildCommand = lib.mkOption {
            description = ''
              The command CI runs to build the web target, derived from the
              options above. Exposed so a build can be reproduced by hand.
            '';
            type = lib.types.str;
            readOnly = true;
          };

          workflowId = lib.mkOption {
            description = ''
              Id of the workflow that builds this web target and ships it. Read-
              only: the build job and every destination job have to agree on it,
              and a rename would break the wiring silently.
            '';
            type = lib.types.str;
            readOnly = true;
          };

          artifact = lib.mkOption {
            description = ''
              Name of the artefact the build job leaves the site in and every
              destination job reads back. Derived for the same reason as
              `workflowId`.
            '';
            type = lib.types.str;
            readOnly = true;
          };

          identity = lib.mkOption {
            description = ''
              What a build calls itself. The same two values reach the
              application as dart-defines and Sentry as the release and
              distribution, which is what lets a report be read against the
              sources it came from.

              Command substitutions rather than a step that exports them, so the
              build command the flake prints reproduces a CI build.
            '';
            type = lib.types.attrsOf lib.types.str;
            readOnly = true;
          };

          outputPath = lib.mkOption {
            description = ''
              Where `flutter build web` writes the site, relative to the
              project. The framework's choice, exposed only so `extraSteps`
              reads the same path the build does.
            '';
            type = lib.types.str;
            readOnly = true;
            default = "build/web";
          };

          extraSteps = lib.mkOption {
            description = ''
              Further GitHub Actions steps to run after the web target is built
              and before it is uploaded as the artefact every destination reads
              from.

              For whatever a project needs that the standards do not know about
              and that has to see the built output on disk. Runs in the build's
              job with the working directory unchanged, so a step here reads and
              writes `outputPath` as the build did.
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

          workflowId = "dart-web${standardsLib.suffix name}";
          artifact = "web${standardsLib.suffix name}";

          identity = {
            # `--long` even on a tag, so that two versions in two bug
            # reports can be compared without knowing which was a release.
            version = "$(git describe --tags --long --always)";

            commit = "$(git rev-parse HEAD)";
          };

          buildCommand = lib.concatStringsSep " " (
            [
              "flutter build web"
              "--release"
            ]
            ++ lib.optional config.web.wasm "--wasm"
            ++ lib.optional (!config.web.webResourcesCdn) "--no-web-resources-cdn"
            ++ lib.optionals config.web.version.enable [
              ''--dart-define=version="${config.web.identity.version}"''
              ''--dart-define=commit="${config.web.identity.commit}"''
            ]
            # The compiler drops the maps unless asked.
            ++ lib.optional config.web.sentry.enable "--source-maps"
            ++ config.web.buildArgs
          );
        };
      }
    ))
  ];
}
