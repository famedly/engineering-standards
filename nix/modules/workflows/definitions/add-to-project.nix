{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghSecret;
in
{
  options.projectUrl = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "URL of the GitHub project board.";
    example = "https://github.com/orgs/famedly/projects/42";
  };

  config.definition = {
    name = "Add Issue to Project";
    on.issues.types = [ "opened" ];
    jobs.add-to-project = {
      name = "Add issue to project";
      runsOn = "ubuntu-latest";
      steps = [
        {
          uses = av."actions/add-to-project";
          with_ = {
            project-url = config.projectUrl;
            github-token = ghSecret "ADD_ISSUE_TO_PROJECT_PAT";
          };
        }
      ];
    };
  };
}
