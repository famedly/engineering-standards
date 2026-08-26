## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# We assemble this from nixpkgs, so that everything in the image follows from
# the repository's lockfile.
#
# `static-web-server` is one static binary and no configuration language,
# which is all a container behind an ingress needs, since TLS, routing and
# redirects happen there. It also types `.mjs` and `.wasm` correctly on its
# own, which a Flutter web build depends on and which the nginx image it
# replaces had to be taught.
{ lib, flake-parts-lib, ... }: {
  imports = [
    (import ../../lib/image-output.nix { inherit lib flake-parts-lib; } {
      name = "dartWebImages";
      file = ./image.nix;
      description = ''
        Images serving the projects' web builds, keyed by project. Each takes
        the built site as `{ site = ...; }` and returns the image.
      '';
    })
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }: {
            # This covers both what goes into the image and what CI does with
            # it, since the workflow reads half of these options too.
            options.web.image = {
              enable = lib.mkEnableOption "building and pushing a container image that serves this web target";

              documentRoot = lib.mkOption {
                description = "Absolute path the site is served from.";
                type = lib.types.strMatching "/.+";
                default = "/srv/www";
              };

              cacheControl = lib.mkOption {
                description = ''
                  Whether to let the server send `Cache-Control` headers.

                  This is off by default, since the server's heuristic caches
                  every file for a day, including the entry document, and a
                  browser would then sit on yesterday's build for a day after
                  a deployment. Validators are sent either way.

                  Turn it on for a site whose file names are content-hashed
                  throughout.
                '';
                type = lib.types.bool;
                default = false;
              };

              headers = lib.mkOption {
                description = ''
                  Headers the server sends with every response.

                  We don't set a `Content-Security-Policy` here, since a
                  policy that fits one application forbids another one's
                  inline bootstrap. That one belongs to the project.
                '';

                type = lib.types.attrsOf lib.types.str;

                default = {
                  X-Content-Type-Options = "nosniff";
                  Referrer-Policy = "strict-origin-when-cross-origin";
                  Permissions-Policy = "camera=(), microphone=(), geolocation=(), payment=(), usb=()";
                  X-Frame-Options = "DENY";

                  # The ingress sends this too, but a mistake there shouldn't
                  # leave the door open.
                  Strict-Transport-Security = "max-age=63072000; includeSubDomains";
                };
              };

              sentHeaders = lib.mkOption {
                description = ''
                  What the server is actually configured with, which is
                  `headers` plus the isolation pair when
                  `crossOriginIsolation` asks for it. We derive it so that the
                  image and the test which fetches from it can't disagree.
                '';

                type = lib.types.attrsOf lib.types.str;
                readOnly = true;

                default =
                  config.web.image.headers
                  // lib.optionalAttrs config.web.image.crossOriginIsolation {
                    Cross-Origin-Opener-Policy = "same-origin";
                    Cross-Origin-Embedder-Policy = "require-corp";
                  };

                defaultText = "the headers above, plus the isolation pair when it is enabled";
              };

              crossOriginIsolation = lib.mkOption {
                description = ''
                  Whether to ask the browser for cross-origin isolation.

                  This is off by default, since
                  `Cross-Origin-Embedder-Policy` blocks every cross-origin
                  resource that doesn't opt in, such as fonts, images and
                  frames.

                  Turn it on for a Flutter web build with the threaded
                  renderer, which needs a `SharedArrayBuffer`.
                '';

                type = lib.types.bool;
                default = false;
              };

              contentTypes = lib.mkOption {
                description = ''
                  Content types the image is expected to serve, keyed by file
                  extension, and checked against the site's own files.

                  A browser won't execute a module script that isn't typed as
                  JavaScript, and won't instantiate a WebAssembly module that
                  isn't typed as such, so serving these wrong takes the whole
                  application down where no build step is watching.

                  We skip extensions the site has no file for.
                '';
                type = lib.types.attrsOf lib.types.str;
                default = {
                  mjs = "application/javascript";
                  wasm = "application/wasm";
                };
              };

              runners = {
                arm64 = lib.mkOption {
                  description = ''
                    Runner that assembles the arm64 image. The standard one is
                    enough, since only the server in this image is
                    architecture-specific.
                  '';
                  type = lib.types.str;
                  default = "ubuntu-24.04-arm";
                };
              };
            };
          }
        )
      );
    };
  });

  config.perSystem =
    {
      config,
      pkgs,
      standardsLib,
      ...
    }:
    let
      projects = lib.filterAttrs (
        _: project: project.web.enable && project.web.image.enable
      ) config.famedly.standards.dart.projects;

      mkImage =
        projectConfig:
        # This is a function because building the site needs network access
        # and credentials for our private repositories, neither of which a
        # build sandbox has. Everything except the site is optional, since a
        # build by hand has no commit to name.
        {
          site,
          source ? null,
          revision ? null,
          version ? null,
        }:
        let
          cfg = projectConfig.web.image;

          # Only what this deployment uses. The rest is not merely unused:
          # `http2` compiles in a TLS stack and `directory-listing-download` a
          # tar reader, and between them they carried every advisory the
          # scanner had to report — about code that cannot run in a container
          # which terminates no TLS and lists no directories. Reducing the
          # features leaves 44 crates out, and the report empty.
          #
          # `compression` earns its place: the server only compresses what it
          # was built to, and the bundle is megabytes of JavaScript and wasm.
          # `fallback-page` pulls in no dependency at all and is what a single
          # page application's deep links need.
          server =
            let
              features = [
                "compression"
                "fallback-page"
              ];
            in
            pkgs.static-web-server.overrideAttrs {
              cargoBuildNoDefaultFeatures = true;
              cargoCheckNoDefaultFeatures = true;

              cargoBuildFeatures = features;
              cargoCheckFeatures = features;
            };

          # Relative, since the commands below run at the image root.
          root = lib.escapeShellArg (lib.removePrefix "/" cfg.documentRoot);

          settingsPath = "/etc/static-web-server.toml";

          # Headers are the one thing the server takes only from a file.
          settings = (pkgs.formats.toml { }).generate "static-web-server.toml" {
            advanced.headers = [
              {
                source = "/**";
                headers = cfg.sentHeaders;
              }
            ];
          };

          labels = standardsLib.ociLabels {
            inherit source revision version;
            title = cfg.name;
          };
        in
        pkgs.dockerTools.streamLayeredImage {
          inherit (cfg) name;
          tag = "latest";

          # We copy the site in rather than handing it to `contents`, which
          # would symlink the store at the document root. The server refuses a
          # path that resolves outside `--root`, so it would serve nothing but
          # 404s.
          #
          # Nothing else goes into the image: no `/etc/passwd`, no CA bundle,
          # no shell. The server looks up no user and opens no connection.
          extraCommands = ''
            mkdir -p ${root} etc
            cp -r ${site}/. ${root}/
            cp ${settings} .${settingsPath}
          '';

          # The build user means nothing inside the image.
          fakeRootCommands = ''
            chown -R 0:0 .
          '';

          config = {
            Cmd = [
              "${server}/bin/static-web-server"
              "--root"
              cfg.documentRoot

              # Not the server's own `::`, since a container without an IPv6
              # stack fails to bind it and our pods are addressed over IPv4.
              "--host"
              "0.0.0.0"

              "--port"
              (toString cfg.port)

              "--cache-control-headers"
              (lib.boolToString cfg.cacheControl)

              "--config-file"
              settingsPath

              # The endpoint Kubernetes probes, which stays out of the log.
              "--health"
            ];

            Labels = labels;

            User = "${toString cfg.user.uid}:${toString cfg.user.gid}";

            ExposedPorts."${toString cfg.port}/tcp" = { };
          };
        };
    in
    {
      dartWebImages = lib.mapAttrs (_: mkImage) projects;
    };
}
