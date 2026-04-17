{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghSecret ciConcurrency;
in
{
  options.model = lib.mkOption {
    type = lib.types.str;
    default = "claude-sonnet-4-5";
    description = "Claude model to use for the review.";
  };

  config.definition = {
    name = "AI Code Review";
    on.pullRequest = {
      branches = [ "**" ];
      types = [
        "opened"
        "reopened"
        "synchronize"
        "ready_for_review"
      ];
    };
    permissions = {
      contents = "read";
      pull-requests = "write";
    };
    concurrency = ciConcurrency;
    jobs.review = {
      runsOn = "ubuntu-latest";
      if_ = "github.event_name == 'pull_request'";
      steps = [
        { uses = av."actions/checkout"; }
        {
          uses = av."anthropics/claude-code-action";
          with_ = {
            anthropic_api_key = ghSecret "ANTHROPIC_API_KEY";
            inherit (config) model;
          };
        }
      ];
    };
  };
}
