## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  standardsLib,
  ...
}:
let
  inherit (config.famedly.standards.ci) steps;
  inherit (standardsLib) directory inProject suffix;

  imageWorkflow = standardsLib.imageWorkflow { inherit config; };

  # `github.workflow` cannot serve here: it holds the display name.
  workflowId = project: "dart-image${suffix project}";
in
{
  perSystem =
    { config, ... }:
    let
      projects = lib.filterAttrs (
        _: project: project.image.enable
      ) config.famedly.standards.dart.projects;

      mkWorkflow =
        project: projectConfig:
        let
          cfg = projectConfig.image;
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

          # A queue needs to see the build and the gate. Publishing skips
          # itself there: the queue's ref would make a nonsense tag.
          on.mergeGroup = { };

          concurrency = {
            group = "${workflowId project}-\${{ github.ref }}";
            cancelInProgress = true;
          };

          jobs = {
            build = imageWorkflow.buildJob {
              inherit (cfg) runners;

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

                  (imageWorkflow.buildStep {
                    inherit project;

                    name = "Build the image";
                    output = "dartImages";
                    arguments = "server = ./${directory project}${cfg.binary};";
                  })
                ]
                ++ lib.optional (cfg.healthPath != null) {
                  # The image is what ships, so it is what gets tested: a
                  # binary that runs on the runner but not in the image used to
                  # ship unnoticed. Polling the image's own healthcheck rather
                  # than the endpoint verifies that too.
                  name = "Smoke test the image";
                  run = ''
                    docker load <image-''${{ matrix.architecture }}.tar

                    # Runners are reused and a container outlives a cancelled
                    # job, so one cancellation would fail every later run.
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
                ++ [ imageWorkflow.uploadStep ];
            };

            publish = imageWorkflow.publishJob {
              needs = [ "build" ] ++ lib.optional (cfg.gate != null) "gate";
              reference = imageWorkflow.reference cfg;
              lockfile = "${directory project}pubspec.lock";
              release = config.famedly.standards.release.enable;
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
