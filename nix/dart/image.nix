## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Images are assembled from nixpkgs rather than from a distro base image.
# Artefacts compiled in the devshell carry nix store paths — `dart compile exe`
# copies the SDK's `dartaotruntime`, so the binary inherits the loader nixpkgs
# patched into it — and no distro base image can resolve those. Building the
# image from the same nixpkgs is what keeps the two from drifting apart.
{ lib, flake-parts-lib, ... }:
{
  imports = [
    (import ../lib/image-output.nix { inherit lib flake-parts-lib; } {
      name = "dartImages";
      file = ./image.nix;
      description = ''
        Images for the projects' servers, keyed by project. Each takes the
        compiled binary as `{ server = ...; }` and returns the image.
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
              options.image = {
                files = lib.mkOption {
                  description = ''
                    Files to place in the image, keyed by their absolute
                    destination. Directories are copied recursively.
                  '';
                  type = lib.types.attrsOf lib.types.path;
                  default = { };
                  example = lib.literalExpression ''
                    {
                      "/app/openapi.yaml" = ./openapi.yaml;
                      "/app/assets" = ./assets;
                    }
                  '';
                };

                port = lib.mkOption {
                  description = "Port the service listens on.";
                  type = lib.types.port;
                  default = 8080;
                };

                healthPath = lib.mkOption {
                  description = ''
                    Path of the health endpoint, or `null` for no healthcheck.
                    Adds `curl` to the image.
                  '';
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "/api/v1/health";
                };

                workdir = lib.mkOption {
                  description = "Working directory of the service.";
                  type = lib.types.str;
                  default = "/app";
                };

                writableDirs = lib.mkOption {
                  description = ''
                    Absolute paths of directories created up front and handed to
                    the service user, for state that is written before a volume
                    is mounted over it.
                  '';
                  type = lib.types.listOf (lib.types.strMatching "/.+");
                  default = [ ];
                  example = [ "/app/data" ];
                };

                user = {
                  name = lib.mkOption {
                    description = "Name of the unprivileged user the service runs as.";
                    type = lib.types.str;
                    default = "app";
                  };

                  uid = lib.mkOption {
                    description = "Uid of the service user.";
                    type = lib.types.int;
                    default = 10001;
                  };

                  gid = lib.mkOption {
                    description = "Gid of the service user.";
                    type = lib.types.int;
                    default = config.image.user.uid;
                    defaultText = "config.image.user.uid";
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
        _: project: project.image.enable
      ) config.famedly.standards.dart.projects;

      # Durations in an OCI image config are nanoseconds.
      seconds = count: count * 1000000000;

      mkImage =
        projectConfig:
        # Kept a function so the compiled binary can be handed in from CI:
        # `dart pub get` needs credentials for our private repositories, which
        # rules out resolving dependencies inside a build sandbox.
        { server }:
        let
          cfg = projectConfig.image;

          user = cfg.user;

          libraries = [ pkgs.glibc ] ++ projectConfig.runtime.libraries;

          # Do not be tempted to patchelf this. `dart compile exe` appends the
          # AOT snapshot behind the end of the `dartaotruntime` ELF, and
          # rewriting the ELF moves it out of reach — the binary then still
          # starts, but as a bare VM printing its usage.
          #
          # It needs no fixing up anyway: the binary carries the loader of the
          # SDK that produced it, which is this nixpkgs'. That is why the
          # architectures are built natively rather than cross-compiled.
          binary = pkgs.runCommand "${cfg.binary}-image-binary" { } ''
            install -Dm555 ${server} $out/bin/${cfg.binary}
          '';

          files = pkgs.runCommand "${cfg.name}-files" { } (
            # `$out` has to be created unconditionally: a project that places no
            # files would otherwise leave the builder without output.
            ''
              mkdir -p "$out"
            ''
            + lib.concatLines (
              lib.mapAttrsToList (target: source: ''
                mkdir -p "$out"${lib.escapeShellArg (builtins.dirOf target)}
                cp -r ${source} "$out"${lib.escapeShellArg target}
              '') cfg.files
            )
          );

          # `fakeNss` is not overridable in our nixpkgs and only knows root and
          # nobody, while the service wants its own uid. nsswitch.conf matters
          # as well: without it glibc resolves no hostnames.
          nss = pkgs.runCommand "${cfg.name}-nss" { } ''
            mkdir -p $out/etc
            cat >$out/etc/passwd <<'EOF'
            root:x:0:0:System administrator:/root:/sbin/nologin
            ${user.name}:x:${toString user.uid}:${toString user.gid}::${cfg.workdir}:/sbin/nologin
            EOF
            cat >$out/etc/group <<'EOF'
            root:x:0:
            ${user.name}:x:${toString user.gid}:
            EOF
            echo 'hosts: files dns' >$out/etc/nsswitch.conf
          '';

          # Image contents land at the root, so packages' `bin` directories merge
          # into `/bin`. The project's own variables win over ours.
          environment = {
            PATH = "/bin";

            # The same variable the devshell relies on, for the same reason:
            # the binary has no RUNPATH to point `dlopen` at.
            LD_LIBRARY_PATH = lib.makeLibraryPath libraries;
          }
          // projectConfig.runtime.env;
        in
        pkgs.dockerTools.streamLayeredImage {
          inherit (cfg) name;
          tag = "latest";

          contents = [
            files
            nss
            pkgs.dockerTools.caCertificates
          ]
          ++ lib.optional (cfg.healthPath != null) pkgs.curl;

          # Runs under fakeroot, which is what lets us hand directories to a
          # user that only exists inside the image.
          # The working directory is the image root, so the paths are relative.
          fakeRootCommands = ''
            mkdir -p tmp
            chmod 1777 tmp

            ${lib.concatLines (
              map (
                directory:
                let
                  path = lib.escapeShellArg (lib.removePrefix "/" directory);
                in
                ''
                  mkdir -p ${path}
                  chown -R ${toString user.uid}:${toString user.gid} ${path}
                ''
              ) cfg.writableDirs
            )}
          '';

          config = {
            Cmd = [ "${binary}/bin/${cfg.binary}" ];
            WorkingDir = cfg.workdir;
            User = "${toString user.uid}:${toString user.gid}";

            ExposedPorts."${toString cfg.port}/tcp" = { };

            Env = lib.mapAttrsToList (name: value: "${name}=${value}") environment;
          }
          // lib.optionalAttrs (cfg.healthPath != null) {
            Healthcheck = {
              Test = [
                "CMD"
                "curl"
                "-fsS"
                "http://127.0.0.1:${toString cfg.port}${cfg.healthPath}"
              ];

              Interval = seconds 30;
              Timeout = seconds 5;
              StartPeriod = seconds 30;
              Retries = 3;
            };
          };
        };
    in
    {
      dartImages = lib.mapAttrs (_: mkImage) projects;
    };
}
