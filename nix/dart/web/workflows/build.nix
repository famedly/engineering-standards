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
  inherit (standardsLib) suffix;
in
{
  perSystem =
    { config, ... }:
    let
      projects = lib.filterAttrs (_: project: project.web.enable) config.famedly.standards.dart.projects;

      # `assets.nix` builds one of these only for a project that needs it.
      assets = project: "dart-web-assets${suffix project}";

      mkWorkflow =
        project: projectConfig:
        assert lib.assertMsg projectConfig.flutter ''
          famedly.standards.dart.projects."${project}": web.enable needs flutter = true, since a plain Dart project has no web target.
        '';
        {
          name = "Build and deploy the web target${
            lib.optionalString (project != ".") " (${lib.removePrefix "./" project})"
          }";

          # The floor for every job here, the ones that publish raise it.
          permissions.contents = "read";

          on.pullRequest.branches = [ "**" ];
          on.push = {
            branches = [ "main" ];
            tags = [ "v*" ];
          };

          # A queue needs to see that the target still builds, the
          # destinations skip themselves there.
          on.mergeGroup = { };

          concurrency = {
            group = "${projectConfig.web.workflowId}-\${{ github.ref }}";
            cancelInProgress = true;
          };

          jobs.build = {
            runsOn = "ubuntu-latest";

            # A hung build would otherwise hold the queue for six hours.
            timeoutMinutes = 45;

            steps =
              # A shallow clone carries no tags for `git describe`.
              (if projectConfig.web.version.enable then steps.withHistory steps.setup else steps.setup)
              ++ lib.optionals projectConfig.checks.privateDependencies steps.privateDependencies
              ++ lib.optional (config.packages ? ${assets project}) {
                name = "Assemble the assets the web target needs";
                shell = steps.devshell;
                run = assets project;
              }
              ++ [
                {
                  name = "Build the web target";
                  shell = steps.devshell;
                  run = ''
                    cd ${project}
                    projectConfig.web.buildCommand
                  '';
                }
              ]
              ++ projectConfig.web.extraSteps
              ++ lib.optionals projectConfig.web.sentry.enable [
                {
                  name = "Hand the debug symbols to Sentry";

                  # A queue's build is thrown away, and Dependabot's requests
                  # have no access to the token.
                  if_ = "github.event_name != 'merge_group' && github.actor != 'dependabot[bot]'";

                  shell = steps.devshell;
                  env.SENTRY_AUTH_TOKEN = "\${{ secrets.SENTRY_AUTH_TOKEN }}";

                  # Not in `env`, where GitHub only interpolates its own
                  # expressions and leaves command substitutions as plain
                  # characters.
                  run = ''
                    cd ${project}
                    SENTRY_RELEASE="${projectConfig.web.identity.version}" \
                    	SENTRY_DIST="${projectConfig.web.identity.commit}" \
                    	dart run sentry_dart_plugin
                  '';
                }

                {
                  # A map left in the build directory is served with the site
                  # and hands out the source the bundle was compiled from.
                  # Unlike the upload this runs unconditionally, since a run
                  # that skipped the upload built the maps all the same.
                  name = "Take the source maps back out of the build";

                  run = ''
                    cd ${project}
                    find ${projectConfig.web.outputPath} \( -name '*.js.map' -o -name '*.wasm.map' \) -delete
                  '';
                }
              ]
              ++ [
                {
                  uses = allowed-actions."actions/upload-artifact".uses;

                  with_ = {
                    name = projectConfig.web.artifact;

                    # A single directory is uploaded without its own prefix, so
                    # the artefact holds the site at its root.
                    path = "${project}/${projectConfig.web.outputPath}";

                    # The deployments replace what they find, so an empty
                    # artefact wouldn't fail, it would erase.
                    if-no-files-found = "error";

                    retention-days = 1;
                  };
                }
              ];
          };
        };
    in
    {
      githubActions.workflows = lib.mapAttrs' (
        project: projectConfig:
        lib.nameValuePair projectConfig.web.workflowId (mkWorkflow project projectConfig)
      ) projects;
    };
}
