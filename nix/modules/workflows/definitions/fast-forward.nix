{
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
in
{
  config.definition = {
    name = "Fast-forward merge";
    on.issueComment.types = [ "created" ];
    permissions = {
      contents = "write";
      pull-requests = "write";
    };
    jobs.fast-forward = {
      runsOn = "ubuntu-latest";
      if_ = "github.event.issue.pull_request && contains(github.event.comment.body, '/fast-forward')";
      steps = [
        {
          uses = "sequoia-pgp/fast-forward@${av.fastForward}";
          with_.merge = true;
        }
      ];
    };
  };
}
