{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
in
{
  config.definition = {
    name = "Authenticate commits";
    on.pullRequest = { };
    jobs.authenticate-commits = {
      runsOn = "ubuntu-latest";
      permissions = {
        contents = "read";
        pull-requests = "write";
        issues = "write";
      };
      steps = [
        {
          name = "Authenticating commits";
          uses = "sequoia-pgp/authenticate-commits@${av.authenticateCommits}";
        }
      ];
    };
  };
}
