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
  inherit (standardsLib) directory inProject suffix;
  inherit (import ../workflow-ids.nix { inherit lib; }) artifact workflowId;

  identity = import ../identity.nix;
in
{
  config.perSystem =
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

          # The floor for every job here; the ones that publish raise it.
          permissions.contents = "read";

          on.pullRequest.branches = [ "**" ];
          on.push = {
            branches = [ "main" ];
            tags = [ "v*" ];
          };

          # A merge queue most needs to see that the target still builds. The
          # destinations skip themselves there: the queue's ref is a temporary
          # branch, so anything published from it would be named nonsense.
          on.mergeGroup = { };

          concurrency = {
            group = "${workflowId project}-\${{ github.ref }}";
            cancelInProgress = true;
          };

          jobs.build = {
            runsOn = "ubuntu-latest";

            # To catch a hung build: a runner waiting for what never comes
            # holds the queue for six hours otherwise.
            timeoutMinutes = 45;

            steps =
              # Deep only where it earns the wait: `git describe` has nothing to
              # describe against in a clone that carries no tags.
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
                  run = inProject project projectConfig.web.buildCommand;
                }
              ]
              ++ projectConfig.web.extraSteps
              ++ lib.optionals projectConfig.web.sentry.enable [
                {
                  name = "Hand the debug symbols to Sentry";

                  # A merge queue's build is thrown away, and nobody can ever
                  # see a report from a build that was never deployed.
                  # Dependabot's pull requests run without access to our
                  # secrets, so this could only ever fail for them.
                  if_ = "github.event_name != 'merge_group' && github.actor != 'dependabot[bot]'";

                  shell = steps.devshell;
                  env.SENTRY_AUTH_TOKEN = "\${{ secrets.SENTRY_AUTH_TOKEN }}";

                  # In the script rather than in `env`, which GitHub takes
                  # literally: it interpolates its own expressions there and
                  # leaves everything else, command substitutions included, as
                  # the characters they are.
                  run = inProject project ''
                    SENTRY_RELEASE="${identity.version}" \
                    	SENTRY_DIST="${identity.commit}" \
                    	dart run sentry_dart_plugin
                  '';
                }

                {
                  # A map left in the build directory is served with the site,
                  # and hands anyone who asks for it the source the bundle was
                  # compiled from. Sentry has them now, and it is the only one
                  # that should.
                  #
                  # Unconditional, unlike the upload above: a run that skipped
                  # it built the maps all the same, and that artefact reaches
                  # the same places as any other.
                  name = "Take the source maps back out of the build";

                  run = inProject project ''
                    find ${projectConfig.web.outputPath} \( -name '*.js.map' -o -name '*.wasm.map' \) -delete
                  '';
                }
              ]
              ++ [
                {
                  uses = allowed-actions."actions/upload-artifact".uses;

                  with_ = {
                    name = artifact project;

                    # A single directory is uploaded without its own prefix, so
                    # the artefact holds the site at its root.
                    path = "${directory project}${projectConfig.web.outputPath}";

                    # A build that produced nothing would otherwise pass this
                    # step and reach the deployments, which replace what they
                    # find: an empty artefact does not fail, it erases.
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
        project: projectConfig: lib.nameValuePair (workflowId project) (mkWorkflow project projectConfig)
      ) projects;
    };
}
