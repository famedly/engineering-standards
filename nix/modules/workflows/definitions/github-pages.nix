{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghExpr;
in
{
  options.artifactName = lib.mkOption {
    type = lib.types.str;
    default = "github-pages";
    description = "Name of the build artifact to publish.";
  };

  config.definition = {
    name = "Publish to GitHub Pages";
    on.workflowRun = {
      workflows = [ "CI" ];
      types = [ "completed" ];
      branches = [ "main" ];
    };
    permissions = {
      pages = "write";
      id-token = "write";
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
          uses = "actions/download-artifact@${av.downloadArtifact}";
          with_ = {
            name = config.artifactName;
            path = "dist";
          };
        }
        { uses = "actions/configure-pages@${av.configurePages}"; }
        {
          uses = "actions/upload-pages-artifact@${av.uploadPagesArtifact}";
          with_.path = "dist";
        }
        {
          id = "deploy";
          uses = "actions/deploy-pages@${av.deployPages}";
        }
      ];
    };
  };
}
