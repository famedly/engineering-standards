{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghExpr ghSecret;
in
{
  options = {
    artifactName = lib.mkOption {
      type = lib.types.str;
      default = "github-pages";
      description = "Name of the build artifact to publish.";
    };

    triggerWorkflows = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "CI" ];
      description = "Names of workflows whose completion triggers the Pages deployment.";
    };

    triggerBranches = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "main" ];
      description = "Only deploy when the triggering workflow ran on these branches.";
    };
  };

  config.definition = {
    name = "Publish to GitHub Pages";
    on.workflowRun = {
      workflows = config.triggerWorkflows;
      types = [ "completed" ];
      branches = config.triggerBranches;
    };
    permissions = {
      pages = "write";
      id-token = "write";
      actions = "read";
    };
    jobs.deploy = {
      runsOn = "ubuntu-latest";
      if_ = "github.event.workflow_run.conclusion == 'success'";
      environment = {
        name = "github-pages";
        url = ghExpr "steps.deploy.outputs.page_url";
      };
      steps = [
        {
          uses = av."actions/download-artifact";
          with_ = {
            name = config.artifactName;
            path = "dist";
            run-id = ghExpr "github.event.workflow_run.run_id";
            github-token = ghSecret "GITHUB_TOKEN";
          };
        }
        { uses = av."actions/configure-pages"; }
        {
          uses = av."actions/upload-pages-artifact";
          with_.path = "dist";
        }
        {
          id = "deploy";
          uses = av."actions/deploy-pages";
        }
      ];
    };
  };
}
