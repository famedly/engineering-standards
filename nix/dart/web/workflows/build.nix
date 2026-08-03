{ config, lib, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
  inherit (import ../../../lib/project-paths.nix { inherit lib; }) directory inProject suffix;
  inherit (import ../workflow-ids.nix { inherit lib; }) artifact workflowId;

  # The directory `flutter build web` writes to. Not an option: it is the
  # framework's choice, not ours.
  output = "build/web";
in
{
  config.perSystem =
    { config, ... }:
    let
      projects = lib.filterAttrs (_: project: project.web.enable) config.famedly.standards.dart.projects;

      # `assets.nix` builds one of these for a project whose `web/` needs
      # something compiled first, and none for a project that needs nothing.
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

          # The floor every job in this workflow starts from, so that one added
          # later reads the repository and nothing more until it says otherwise.
          # The jobs that publish something raise it themselves.
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

            # A ceiling meant to catch a build that hangs, not to hurry one
            # that works: a runner that waits for something which will never
            # come otherwise holds the queue for six hours.
            timeoutMinutes = 45;

            steps =
              steps.setup
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

                {
                  uses = allowed-actions."actions/upload-artifact".uses;

                  with_ = {
                    name = artifact project;

                    # A single directory is uploaded without its own prefix, so
                    # the artefact holds the site at its root.
                    path = "${directory project}${output}";

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
