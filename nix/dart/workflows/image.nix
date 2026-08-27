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
  inherit (standardsLib) makeValidGitHubWorkflowID;

  imageWorkflow = standardsLib.imageWorkflow { inherit config; };

  # We can't use `github.workflow` for this, it holds the display name.
  workflowId = project: "dart-image${makeValidGitHubWorkflowID project}";
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

          container = "smoke${makeValidGitHubWorkflowID project}";
        in
        {
          name = "Build and push the container image${
            lib.optionalString (project != ".") " (${lib.removePrefix "./" project})"
          }";

          # The floor for every job here, the job that publishes raises it.
          permissions.contents = "read";

          on.pullRequest.branches = [ "**" ];
          on.push = {
            branches = [ "main" ];
            tags = [ "v*" ];
          };

          # A queue needs to see the build and the gate. Publishing skips
          # itself there, since the queue's ref would make a nonsense tag.
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
                    run = ''
                      cd ${project}
                      dart pub get
                      dart compile exe ${cfg.entrypoint} -o ${cfg.binary}
                    '';
                  }

                  (imageWorkflow.buildStep {
                    inherit project;

                    name = "Build the image";
                    output = "dartImages";

                    artefact = {
                      name = "server";
                      path = "${project}/${cfg.binary}";
                    };
                  })
                ]
                ++ lib.optional (cfg.healthPath != null) (
                  imageWorkflow.smokeTest {
                    name = "Smoke test the image";

                    inherit container;
                    image = cfg.name;

                    # We poll the image's own healthcheck rather than the
                    # endpoint, which verifies the healthcheck too.
                    options = [ "--health-interval 2s" ];

                    checks = [
                      ''
                        for _ in $(seq 30); do
                          health="$(docker inspect --format '{{.State.Health.Status}}' ${container})"
                          test "$health" = starting || break
                          sleep 2
                        done

                        test "$health" = healthy
                      ''
                    ];
                  }
                )
                ++ [ imageWorkflow.uploadStep ];
            };

            publish = imageWorkflow.publishJob {
              needs = [ "build" ] ++ lib.optional (cfg.gate != null) "gate";
              reference = imageWorkflow.reference cfg;
              lockfile = "${project}/pubspec.lock";
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

      # The registry a tag is pushed to, which is the one a release refers to.
      famedly.standards.release.signedImages = lib.mapAttrsToList (project: projectConfig: {
        reference = "${projectConfig.image.releaseRegistry}/${projectConfig.image.name}";
        workflow = "${workflowId project}.yml";
      }) projects;
    };
}
