{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ciConcurrency;
in
{
  config.definition = {
    name = "REUSE compliance";
    on.pullRequest = { };
    permissions.contents = "read";
    concurrency = ciConcurrency;
    jobs.reuse = {
      runsOn = "ubuntu-latest";
      steps = [
        { uses = "actions/checkout@${av.checkout}"; }
        { uses = "fsfe/reuse-action@${av.reuseAction}"; }
      ];
    };
  };
}
