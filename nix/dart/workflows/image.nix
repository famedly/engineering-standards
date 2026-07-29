{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
  inherit (import ../project-paths.nix { inherit lib; }) directory inProject suffix;

  # One workflow per project, so anything that has to distinguish them keys off
  # this. `github.workflow` cannot: it holds the display name.
  workflowId = project: "dart-image${suffix project}";

  architectures = [
    "amd64"
    "arm64"
  ];
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              options.image = {
                enable = lib.mkEnableOption "building and pushing a container image for this project";

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

                name = lib.mkOption {
                  description = ''
                    Name of the image to push, without the registry.
                  '';
                  type = lib.types.str;
                  example = "famedly-headless";
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
                    description = "Runner that builds the arm64 image.";
                    type = lib.types.str;
                    default = "arm-ubuntu-latest-8core";
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
    }
  );

  config.perSystem =
    { config, ... }:
    let
      projects = lib.filterAttrs (
        _: project: project.image.enable
      ) config.famedly.standards.dart.projects;

      # Building the image from nixpkgs means the artefacts and their libraries
      # share a glibc, so the arch-specific jobs run natively rather than
      # cross-compiling.
      mkWorkflow =
        project: projectConfig:
        let
          cfg = projectConfig.image;

          gated = [ "build" ] ++ lib.optional (cfg.gate != null) "gate";

          registry = "\${{ github.event_name == 'pull_request' && '${cfg.nightlyRegistry}' || '${cfg.releaseRegistry}' }}";

          # What `docker/metadata-action` derived for us before: `pr-<number>`
          # for pull requests, the branch or tag name otherwise.
          tag = "\${{ github.event_name == 'pull_request' && format('pr-{0}', github.event.number) || github.ref_name }}";

          reference = "${registry}/${cfg.name}";

          arm64Runner =
            if cfg.runners.arm64Release == cfg.runners.arm64 then
              "'${cfg.runners.arm64}'"
            else
              "(github.event_name == 'push' && '${cfg.runners.arm64Release}' || '${cfg.runners.arm64}')";

          # Pinned like everything else, since it resolves against the
          # repository's own locked nixpkgs.
          publishShell = "nix shell --inputs-from . nixpkgs#manifest-tool nixpkgs#skopeo --command bash -e {0}";
        in
        {
          name = "Build and push the container image${
            lib.optionalString (project != ".") " (${lib.removePrefix "./" project})"
          }";

          on.pullRequest.branches = [ "**" ];
          on.push = {
            branches = [ "main" ];
            tags = [ "v*" ];
          };

          # The checks workflow runs on merge queues, and the build and the gate
          # are what a queue most needs to see. Publishing is skipped there: the
          # queue's ref is a temporary branch and would make a nonsense tag.
          on.mergeGroup = { };

          concurrency = {
            group = "${workflowId project}-\${{ github.ref }}";
            cancelInProgress = true;
          };

          jobs = {
            build = {
              strategy = {
                failFast = false;
                matrix.architecture = architectures;
              };

              runsOn = "\${{ matrix.architecture == 'arm64' && ${arm64Runner} || '${cfg.runners.amd64}' }}";

              steps =
                steps.setup
                ++ lib.optionals projectConfig.checks.privateDependencies steps.privateDependencies
                ++ [
                  {
                    name = "Compile";
                    shell = steps.devshell;
                    run = inProject project ''
                      dart pub get
                      dart compile exe ${cfg.entrypoint} -o ${cfg.binary}
                    '';
                  }

                  {
                    name = "Build the image";
                    # `getAttr` rather than a dynamic attribute, so the
                    # expression carries nothing that looks like a shell
                    # variable to shellcheck.
                    run = ''
                      image="$(nix build --impure --no-link --print-out-paths --expr '
                        let
                          flake = builtins.getFlake (toString ./.);
                          images = builtins.getAttr builtins.currentSystem flake.legacyPackages;
                        in images.dartImages."${project}" {
                          server = ./${directory project}${cfg.binary};
                        }
                      ')"

                      "$image" >image-''${{ matrix.architecture }}.tar
                    '';
                  }
                ]
                ++ lib.optional (cfg.healthPath != null) {
                  # The image is what ships, so it is what gets tested. A binary
                  # that runs on the runner but not in the image is the failure
                  # this catches, and it shipped unnoticed before.
                  #
                  # What is polled is the image's own healthcheck, just at a
                  # tighter interval than production would use — so that gets
                  # verified here too, instead of a second copy of the endpoint.
                  name = "Smoke test the image";
                  run = ''
                    docker load <image-''${{ matrix.architecture }}.tar
                    docker run --detach --name smoke --health-interval 2s ${cfg.name}:latest

                    for _ in $(seq 30); do
                      health="$(docker inspect --format '{{.State.Health.Status}}' smoke)"
                      test "$health" = starting || break
                      sleep 2
                    done

                    docker logs smoke
                    docker rm --force smoke

                    test "$health" = healthy
                  '';
                }
                ++ [
                  {
                    uses = allowed-actions."actions/upload-artifact".uses;

                    with_ = {
                      name = "image-\${{ matrix.architecture }}";
                      path = "image-\${{ matrix.architecture }}.tar";
                      retention-days = 1;
                    };
                  }
                ];
            };

            publish = {
              if_ = "github.event_name != 'merge_group'";
              needs = gated;
              runsOn = "ubuntu-latest";

              steps = steps.setup ++ [
                {
                  uses = allowed-actions."actions/download-artifact".uses;

                  with_ = {
                    pattern = "image-*";
                    path = "images";
                    merge-multiple = true;
                  };
                }

                {
                  name = "Push the images and the manifest list";
                  shell = publishShell;

                  env = {
                    REGISTRY_USER = "\${{ vars.REGISTRY_USER }}";
                    REGISTRY_PASSWORD = "\${{ secrets.registry_password }}";

                    IMAGE = reference;
                    TAG = tag;
                  };

                  run = ''
                    ${lib.concatMapStringsSep "\n" (architecture: ''
                      skopeo copy --dest-creds "$REGISTRY_USER:$REGISTRY_PASSWORD" \
                      	docker-archive:images/image-${architecture}.tar \
                      	"docker://$IMAGE:$TAG-${architecture}"
                    '') architectures}
                    manifest-tool --username "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" \
                    	push from-args \
                    	--platforms ${lib.concatMapStringsSep "," (architecture: "linux/${architecture}") architectures} \
                    	--template "$IMAGE:$TAG-ARCH" \
                    	--target "$IMAGE:$TAG"
                  '';
                }
              ];
            };
          }
          // lib.optionalAttrs (cfg.gate != null) {
            gate = {
              uses = cfg.gate;
              secrets = "inherit";
            };
          };
        };
    in
    {
      githubActions.workflows = lib.mapAttrs' (
        project: projectConfig: lib.nameValuePair (workflowId project) (mkWorkflow project projectConfig)
      ) projects;
    };
}
