## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Assembled from nixpkgs, so everything in the image follows from the
# repository's lockfile.
#
# `static-web-server` is one static binary and no configuration language, which
# is all a container behind an ingress needs — TLS, routing and redirects happen
# there. It also types `.mjs` and `.wasm` correctly on its own, which a Flutter
# web build depends on and the nginx image it replaces had to be taught.
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
            # Both what goes into the image and what CI does with it: the
            # workflow reads half of these too.
            options.web.image = {
              enable = lib.mkEnableOption "building and pushing a container image that serves this web target";

              name = lib.mkOption {
                description = "Name of the image to push, without the registry.";
                type = lib.types.str;
                example = "famedly-control-client";
              };

              port = lib.mkOption {
                description = "Port the server listens on.";
                type = lib.types.port;
                default = 8080;
              };

              documentRoot = lib.mkOption {
                description = "Absolute path the site is served from.";
                type = lib.types.strMatching "/.+";
                default = "/srv/www";
              };

              cacheControl = lib.mkOption {
                description = ''
                  Whether to let the server send `Cache-Control` headers.

                  Off, because its heuristic caches every file for a day,
                  including the entry document — a browser would sit on
                  yesterday's build for a day after a deployment. Validators
                  are sent either way.

                  Turn it on for a site whose file names are content-hashed
                  throughout.
                '';
                type = lib.types.bool;
                default = false;
              };

              headers = lib.mkOption {
                description = ''
                  Headers the server sends with every response.

                  No `Content-Security-Policy`: a policy that fits one
                  application forbids another one's inline bootstrap, so it
                  belongs to the project.
                '';

                type = lib.types.attrsOf lib.types.str;

                default = {
                  X-Content-Type-Options = "nosniff";
                  Referrer-Policy = "strict-origin-when-cross-origin";
                  Permissions-Policy = "camera=(), microphone=(), geolocation=(), payment=(), usb=()";
                  X-Frame-Options = "DENY";

                  # Sent by the ingress as well; a mistake there should not
                  # leave the door open.
                  Strict-Transport-Security = "max-age=63072000; includeSubDomains";
                };
              };

              sentHeaders = lib.mkOption {
                description = ''
                  What the server is configured with: `headers`, plus the
                  isolation pair when `crossOriginIsolation` asks for it.
                  Derived, so the image and the test that fetches from it
                  cannot disagree.
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

                  Off, because `Cross-Origin-Embedder-Policy` blocks every
                  cross-origin resource that does not opt in — fonts, images,
                  frames.

                  Turn it on for a Flutter web build with the threaded
                  renderer, which needs a `SharedArrayBuffer`.
                '';

                type = lib.types.bool;
                default = false;
              };

              user = {
                uid = lib.mkOption {
                  description = "Uid the server runs as.";
                  type = lib.types.int;
                  default = 10001;
                };

                gid = lib.mkOption {
                  description = "Gid the server runs as.";
                  type = lib.types.int;
                  default = config.web.image.user.uid;
                  defaultText = "config.web.image.user.uid";
                };
              };

              contentTypes = lib.mkOption {
                description = ''
                  Content types the image is expected to serve, keyed by file
                  extension, and checked against the site's own files.

                  A browser will not execute a module script that is not typed
                  as JavaScript, nor instantiate a WebAssembly module that is
                  not typed as such, so serving these wrong takes the whole
                  application down where no build step is watching.

                  Extensions the site has no file for are skipped.
                '';
                type = lib.types.attrsOf lib.types.str;
                default = {
                  mjs = "application/javascript";
                  wasm = "application/wasm";
                };
              };

              nightlyRegistry = lib.mkOption {
                description = "Registry images built from pull requests go to.";
                type = lib.types.str;
                default = "registry.famedly.net/docker-nightly";
              };

              releaseRegistry = lib.mkOption {
                description = ''
                  Registry images built from `main` and version tags go to.
                '';
                type = lib.types.str;
                default = "registry.famedly.net/docker-releases";
              };

              runners = {
                amd64 = lib.mkOption {
                  description = "Runner that assembles the amd64 image.";
                  type = lib.types.str;
                  default = "ubuntu-latest";
                };

                arm64 = lib.mkOption {
                  description = ''
                    Runner that assembles the arm64 image. The standard one:
                    only the server in this image is architecture-specific.
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
        # A function, because building the site needs network access and
        # credentials for our private repositories, neither of which a build
        # sandbox has. Everything but the site is optional: a build by hand has
        # no commit to name.
        {
          site,
          source ? null,
          revision ? null,
          version ? null,
        }:
        let
          cfg = projectConfig.web.image;

          server = pkgs.static-web-server;

          # Relative: the commands below run at the image root.
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

          # Copied in rather than handed to `contents`, which would symlink the
          # store at the document root — and the server refuses a path that
          # resolves outside `--root`, so it would serve nothing but 404s.
          #
          # Nothing else is in the image: no `/etc/passwd`, no CA bundle, no
          # shell. The server looks up no user and opens no connection.
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

              # Not the server's own `::`: a container without an IPv6 stack
              # fails to bind it, and our pods are addressed over IPv4.
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
