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
  inherit (standardsLib) directory script suffix;

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
        in
        {
          # Only the server in the image is architecture-specific — the site
          # itself is bytes either way, and was built once in `build`. So these
          # jobs assemble rather than build, and run natively only because the
          # server they wrap has to match the platform it is pushed as.
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
                arguments = "site = ./site;";
              })

              {
                # The image is what ships, so it is what gets tested — a server
                # that starts on the runner but not in the image is the failure
                # this catches. It fetches the site's real files rather than a
                # placeholder, so a missing entry document fails here too.
                name = "Smoke test the image";

                run = script (
                  [
                    ''
                      docker load <image-''${{ matrix.architecture }}.tar

                      # The runners are reused and a container outlives a
                      # cancelled job, so without this one cancellation would
                      # fail every later run on that runner.
                      docker rm --force ${container} 2>/dev/null || true

                      # An ephemeral host port, so that concurrent jobs on a
                      # shared runner cannot collide over one.
                      docker run --detach --name ${container} \
                      	--publish 127.0.0.1::${toString cfg.port} \
                      	${cfg.name}:latest

                      # The server's log and the container go away whichever way
                      # this step ends, so a failure below stays diagnosable.
                      trap 'docker logs ${container}; docker rm --force ${container} >/dev/null' EXIT

                      base="http://$(docker port ${container} ${toString cfg.port}/tcp | head -1)"

                      for _ in $(seq 30); do
                        curl -fsS -o /dev/null "$base/index.html" && break
                        sleep 1
                      done

                      # Again, so that a server which never came up fails the
                      # step rather than only the loop.
                      curl -fsS -o /dev/null "$base/index.html"

                      # What Kubernetes asks before it sends anyone here.
                      curl -fsS -o /dev/null "$base/health"

                      # Read once for the comparisons below. Names come back
                      # lower-cased, so the patterns are folded, not the file.
                      curl -fsSI "$base/index.html" | tr -d '\r' >headers
                    ''
                  ]
                  ++ lib.mapAttrsToList (header: expected: ''
                    sent="$(sed -n 's/^${lib.toLower header}: *//p' headers)"

                    if test "$sent" != ${lib.escapeShellArg expected}; then
                      echo "::error::${header} is sent as '$sent', expected '${expected}'"
                      exit 1
                    fi

                    echo "${header}: $sent"
                  '') cfg.sentHeaders
                  ++ lib.mapAttrsToList (extension: expected: ''
                    file="$(cd site && find . -type f -name '*.${extension}' -print -quit)"

                    if test -n "$file"; then
                      # Header names and media types are both case-insensitive,
                      # so each side is folded once instead of being matched a
                      # letter at a time.
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
                  '') cfg.contentTypes
                );
              }

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
    };
}
