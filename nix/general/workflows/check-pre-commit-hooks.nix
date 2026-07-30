{ config, ... }:
let
  inherit (config.famedly.standards.ci) steps;
in
{
  perSystem.githubActions.workflows.check-pre-commit-hooks = {
    name = "Make sure all pre-commit hooks pass";

    # The floor every job here starts from, so that one added later reads
    # the repository and nothing more until it says otherwise.
    permissions.contents = "read";

    # We don't run these on `push`, since the start and end of the
    # commit series isn't clear in that case.
    #
    # This does mean that you need to have an open PR for workflows
    # against your branch to run, but that's probably reasonable for
    # cost saving purposes anyway.
    on.pullRequest = {
      branches = [ "**" ];
      types = [
        "opened"
        "reopened"
        "synchronize"
        "ready_for_review"
      ];
    };
    on.mergeGroup = { };

    concurrency = {
      group = "\${{ github.workflow }}-\${{ github.ref }}";
      cancelInProgress = true;
    };

    jobs.prek = {
      runsOn = "ubuntu-latest";

      timeoutMinutes = 30;

      steps = steps.setup ++ [
        {
          name = "Run pre-commit hooks";
          shell = steps.devshell;
          run = "prek --all-files --show-diff-on-failure --stage pre-push";
          env = {
            PREK_COLOR = "always";
            # On some CI runners, the cache would time out, causing the pipeline to fail.
            # Since the official documentation (https://treefmt.com/usage/#ci-integration)
            # recommends using `----no-cache` anyway, we add it here.
            #
            # We do not add `--fail-on-change`, since prek takes care of that
            TREEFMT_NO_CACHE = "1";
          };
        }
      ];
    };
  };
}
