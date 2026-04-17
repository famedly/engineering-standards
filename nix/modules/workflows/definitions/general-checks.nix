{
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
    name = "General checks (conventional commits)";
    on.pullRequest = { };
    permissions.contents = "read";
    concurrency = ciConcurrency;
    jobs.conventional_commits = {
      runsOn = "ubuntu-latest";
      if_ = "github.ref != 'refs/heads/main' && github.event.pull_request";
      steps = [
        {
          uses = av."actions/checkout";
          with_.fetch-depth = 0;
        }
        {
          name = "Check conventional commits";
          run = ''
            COMMIT_MSGS=$(git log --no-merges --format=%s origin/main..HEAD)
            FAILED=0
            while IFS= read -r msg; do
              if [[ ! "$msg" =~ ^(ci|feat|fix|docs|style|refactor|perf|test|chore|build|revert)(\(.+\))?:\ .+ ]]; then
                echo "::error::Invalid commit message: $msg"
                FAILED=1
              fi
            done <<< "$COMMIT_MSGS"
            exit $FAILED
          '';
        }
      ];
    };
  };
}
