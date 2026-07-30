# Images are assembled from nixpkgs rather than from a distro base image, so
# that everything in them is derivable from the repository's lockfile.
#
# The server is `static-web-server`: one static binary and no configuration
# language, which is all a container behind an ingress needs — TLS, routing and
# redirects happen there, not here. It also gets the content types a Flutter web
# build depends on right on its own, `.mjs` as `application/javascript` and
# `.wasm` as `application/wasm`. The nginx image this replaces had to patch the
# former in by hand, and the workflow asserts both rather than trusting them.
{ lib, flake-parts-lib, ... }:
{
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

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              options.web.image = {
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
                    including the entry document — which would leave a browser
                    on yesterday's build of a single-page application for a day
                    after a deployment. Validators are still sent, so a
                    revalidating client is served a `304` either way.

                    Turn this on for a site whose file names are
                    content-hashed throughout.
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
              };
            }
          )
        );
      };
    }
  );

  config.perSystem =
    { config, pkgs, ... }:
    let
      projects = lib.filterAttrs (
        _: project: project.web.enable && project.web.image.enable
      ) config.famedly.standards.dart.projects;

      mkImage =
        projectConfig:
        # Kept a function so the built site can be handed in from CI: resolving
        # a project's dependencies needs both network access and credentials for
        # our private repositories, which rules out building inside a sandbox.
        #
        # The rest says where the site came from. All optional, because a build
        # by hand has no commit to speak of — and an image that carries its
        # origin only when there is one to carry is still better than one that
        # never does.
        {
          site,
          source ? null,
          revision ? null,
          version ? null,
        }:
        let
          cfg = projectConfig.web.image;

          server = pkgs.static-web-server;

          # Relative, because the commands below run with the image root as
          # their working directory.
          root = lib.escapeShellArg (lib.removePrefix "/" cfg.documentRoot);

          # No `created`: a timestamp would make two builds of the same commit
          # differ, and the commit these name has a date of its own.
          labels = lib.filterAttrs (_: value: value != null) {
            "org.opencontainers.image.title" = cfg.name;
            "org.opencontainers.image.source" = source;
            "org.opencontainers.image.revision" = revision;
            "org.opencontainers.image.version" = version;
          };
        in
        pkgs.dockerTools.streamLayeredImage {
          inherit (cfg) name;
          tag = "latest";

          # The site is copied in rather than handed to `contents`, which would
          # put a symlink into the store at the document root. The server
          # resolves every request and refuses a path whose resolved form lies
          # outside `--root`, so such a document root serves nothing but 404s —
          # and the store copy would ship twice over.
          #
          # Beyond the site the image holds only the server: no `/etc/passwd`,
          # no CA bundle, no shell. The server neither looks its own user up nor
          # opens an outbound connection, and there is nothing here to exec
          # into. What it cannot reach, it cannot be made to reach.
          extraCommands = ''
            mkdir -p ${root}
            cp -r ${site}/. ${root}/
          '';

          # Files created above carry the build user, which has no meaning
          # inside the image.
          fakeRootCommands = ''
            chown -R 0:0 .
          '';

          config = {
            Cmd = [
              "${server}/bin/static-web-server"
              "--root"
              cfg.documentRoot

              # Not `::`, which is the server's own default: a container without
              # a configured IPv6 stack fails to bind it, and our pods are
              # addressed over IPv4.
              "--host"
              "0.0.0.0"

              "--port"
              (toString cfg.port)

              "--cache-control-headers"
              (lib.boolToString cfg.cacheControl)
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
