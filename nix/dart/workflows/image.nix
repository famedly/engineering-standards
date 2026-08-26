## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
  inherit (import ../../lib/project-paths.nix { inherit lib; }) directory inProject suffix;

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
    { lib, ... }: {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }: {
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
        in
        {
          name = "Build and push the container image${
            lib.optionalString (project != ".") " (${lib.removePrefix "./" project})"
          }";

          # The floor for every job here; the job that publishes raises it.
          permissions.contents = "read";

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

              timeoutMinutes = 30;

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
                    #
                    # `--print-build-logs`, because without it a failure prints
                    # only the path of a log that `nix log` would read — and the
                    # runner that holds it is gone by the time anyone reads the
                    # step.
                    run = ''
                      image="$(nix build --impure --no-link --print-build-logs --print-out-paths --expr '
                        let
                          flake = builtins.getFlake (toString ./.);
                          images = builtins.getAttr builtins.currentSystem flake.dartImages;
                        in images."${project}" {
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

                    # The arm64 runners are self-hosted and reused, and the container
                    # outlives a cancelled job: without this, one cancellation fails
                    # every later run on that runner.
                    docker rm --force smoke 2>/dev/null || true

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

                      # The publishing job reads the archive out of this
                      # artefact, and would push whatever it finds. Nothing is
                      # not an image.
                      if-no-files-found = "error";

                      retention-days = 1;
                    };
                  }
                ];
            };

            publish = {
              if_ = "github.event_name != 'merge_group'";
              needs = gated;
              runsOn = "ubuntu-latest";

              timeoutMinutes = 20;

              # `id-token`, because cosign signs with this workflow's identity
              # rather than with a key. `contents`, only where there is a
              # release to attach the documents to.
              permissions = {
                contents = if config.famedly.standards.release.enable then "write" else "read";
                id-token = "write";
              };

              steps =
                steps.setup
                ++ steps.publishImages {
                  inherit architectures reference tag;
                  lockfile = "${directory project}pubspec.lock";
                  release = config.famedly.standards.release.enable;
                };
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

      # The registry a tag is pushed to, which is the one a release refers to.
      famedly.standards.release.signedImages = lib.mapAttrsToList (project: projectConfig: {
        reference = "${projectConfig.image.releaseRegistry}/${projectConfig.image.name}";
        workflow = "${workflowId project}.yml";
      }) projects;
    };
}
