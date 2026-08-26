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
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
  inherit (standardsLib) directory suffix;

  imageWorkflow = standardsLib.imageWorkflow { inherit config; };
in
{
  perSystem =
    { config, ... }:
    let
      projects = lib.filterAttrs (
        _: project: project.web.enable && project.web.image.enable
      ) config.famedly.standards.dart.projects;

      mkJobs =
        project: projectConfig:
        let
          cfg = projectConfig.web.image;

          container = "smoke-web${suffix project}";

          serve = ''
            base="http://$(docker port ${container} ${toString cfg.port}/tcp | head -1)"

            for _ in $(seq 30); do
              curl -fsS -o /dev/null "$base/index.html" && break
              sleep 1
            done

            # Again, so that a server which never came up fails the step and
            # not just the loop.
            curl -fsS -o /dev/null "$base/index.html"

            # This is what Kubernetes asks before it sends anyone here.
            curl -fsS -o /dev/null "$base/health"

            # Read once for the comparisons below.
            curl -fsSI "$base/index.html" | tr -d '\r' >headers
          '';

          checkHeader = header: expected: ''
            sent="$(sed -n 's/^${lib.toLower header}: *//p' headers)"

            if test "$sent" != ${lib.escapeShellArg expected}; then
              echo "::error::${header} is sent as '$sent', expected '${expected}'"
              exit 1
            fi

            echo "${header}: $sent"
          '';

          checkContentType = extension: expected: ''
            file="$(cd site && find . -type f -name '*.${extension}' -print -quit)"

            if test -n "$file"; then
              # Header names and media types are case-insensitive.
              served="$(curl -fsSI "$base/''${file#./}" \
              	| tr -d '\r' \
              	| tr '[:upper:]' '[:lower:]' \
              	| sed -n 's/^content-type: *//p' \
              	| sed 's/ *;.*//')"

              if test "$served" != '${lib.toLower expected}'; then
                echo "::error::$file is served as '$served', expected '${lib.toLower expected}'"
                exit 1
              fi

              echo "$file is served as $served"
            fi
          '';
        in
        {
          # The site was built once in `build` and is just bytes. Only the
          # server in the image has to match the platform it is pushed as.
          image = imageWorkflow.buildJob {
            inherit (cfg) runners;

            needs = [ "build" ];

            steps = steps.setup ++ [
              {
                uses = allowed-actions."actions/download-artifact".uses;

                with_ = {
                  name = projectConfig.web.artifact;
                  path = "site";
                };
              }

              (imageWorkflow.buildStep {
                inherit project;

                name = "Assemble the image";
                output = "dartWebImages";

                artefact = {
                  name = "site";
                  path = "site";
                };
              })

              (imageWorkflow.smokeTest {
                # It fetches the site's real files, so a missing entry
                # document fails here too.
                name = "Smoke test the image";

                inherit container;
                image = cfg.name;

                # An ephemeral port, so that concurrent jobs can't collide.
                options = [ "--publish 127.0.0.1::${toString cfg.port}" ];

                checks = [
                  serve
                ]
                ++ lib.mapAttrsToList checkHeader cfg.sentHeaders
                ++ lib.mapAttrsToList checkContentType cfg.contentTypes;
              })

              imageWorkflow.uploadStep
            ];
          };

          publish = imageWorkflow.publishJob {
            needs = [ "image" ];
            reference = imageWorkflow.reference cfg;
            lockfile = "${directory project}pubspec.lock";
            release = config.famedly.standards.release.enable;
          };
        };
    in
    {
      githubActions.workflows = lib.mapAttrs' (
        project: projectConfig:
        lib.nameValuePair projectConfig.web.workflowId { jobs = mkJobs project projectConfig; }
      ) projects;

      # The registry a tag is pushed to, which is the one a release refers to.
      famedly.standards.release.signedImages = lib.mapAttrsToList (_: projectConfig: {
        reference = "${projectConfig.web.image.releaseRegistry}/${projectConfig.web.image.name}";
        workflow = "${projectConfig.web.workflowId}.yml";
      }) projects;
    };
}
