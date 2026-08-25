## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Assembled from nixpkgs rather than from a distro base image: `dart compile
# exe` copies the SDK's `dartaotruntime` into the binary, so it carries a nix
# store loader that no distro image can resolve.
{ lib, flake-parts-lib, ... }: {
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

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }: {
            # Both what goes into the image and what CI does with it: the
            # workflow reads half of these too.
            options.image = {
              enable = lib.mkEnableOption "building and pushing a container image for this project";

              name = lib.mkOption {
                description = ''
                  Name of the image to push, without the registry.
                '';
                type = lib.types.str;
                example = "famedly-headless";
              };

              entrypoint = lib.mkOption {
                description = ''
                  The Dart entrypoint to compile into the image.
                '';
                type = lib.types.str;
                default = "bin/server.dart";
              };

              binary = lib.mkOption {
                description = ''
                  Name the entrypoint is compiled to, and the name it gets
                  inside the image.
                '';
                type = lib.types.str;
                default = "server";
              };

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

              nightlyRegistry = lib.mkOption {
                description = ''
                  Registry that images built from pull requests are pushed to.
                '';
                type = lib.types.str;
                default = "registry.famedly.net/docker-nightly";
              };

              releaseRegistry = lib.mkOption {
                description = ''
                  Registry that images built from `main` and version tags are
                  pushed to.
                '';
                type = lib.types.str;
                default = "registry.famedly.net/docker-releases";
              };

              gate = lib.mkOption {
                description = ''
                  A workflow that has to pass before the image is pushed, for
                  test suites that are too project-specific to live in the
                  standards. Called with `secrets: inherit`.
                '';
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "./.github/workflows/test.yaml";
              };

              runners = {
                amd64 = lib.mkOption {
                  description = "Runner that builds the amd64 image.";
                  type = lib.types.str;
                  default = "ubuntu-latest";
                };

                arm64 = lib.mkOption {
                  description = ''
                    Runner that builds the arm64 image.

                    The eight-core alternative costs 2.8 times as much per
                    minute and measured 1.16 times faster here, since half
                    the wait is fetching and unpacking. Name it here for a
                    project whose build really is compilation throughout.
                  '';
                  type = lib.types.str;
                  default = "ubuntu-24.04-arm";
                };

                arm64Release = lib.mkOption {
                  description = ''
                    Runner that builds the arm64 release image, for projects
                    that want to spend more on it than on nightlies.
                  '';
                  type = lib.types.str;
                  default = config.image.runners.arm64;
                  defaultText = "config.image.runners.arm64";
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
        _: project: project.image.enable
      ) config.famedly.standards.dart.projects;

      # Durations in an OCI image config are nanoseconds.
      seconds = count: count * 1000000000;

      mkImage =
        projectConfig:
        # A function, because `dart pub get` needs credentials for our private
        # repositories and so cannot run in a build sandbox. Everything but the
        # binary is optional: a build by hand has no commit to name.
        {
          server,
          source ? null,
          revision ? null,
          version ? null,
        }:
        let
          cfg = projectConfig.image;

          user = cfg.user;

          libraries = [ pkgs.glibc ] ++ projectConfig.runtime.libraries;

          # Do not patchelf this. `dart compile exe` appends the AOT snapshot
          # behind the end of the `dartaotruntime` ELF, and rewriting the ELF
          # moves it out of reach — the binary then starts as a bare VM
          # printing its usage. It needs no fixing either: it carries the
          # loader of this nixpkgs, which is why builds run natively.
          binary = pkgs.runCommand "${cfg.binary}-image-binary" { } ''
            install -Dm555 ${server} $out/bin/${cfg.binary}
          '';

          files = pkgs.runCommand "${cfg.name}-files" { } (
            # A project that places no files must still leave an output.
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

          # Not `fakeNss`: it is not overridable here and knows only root and
          # nobody. Without nsswitch.conf glibc resolves no hostnames.
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

          # Contents land at the root, so `bin` directories merge into `/bin`.
          environment = {
            PATH = "/bin";

            # As in the devshell: the binary has no RUNPATH for `dlopen`.
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

          # Under fakeroot, so directories can be handed to a user that exists
          # only inside the image. Paths are relative to the image root.
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

            Labels = standardsLib.ociLabels {
              inherit source revision version;
              title = cfg.name;
            };

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
