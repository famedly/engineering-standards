{ config, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
in
{
  perSystem.githubActions.workflows.check-pre-commit-hooks = {
    name = "Make sure all pre-commit hooks pass";

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

    concurrency = {
      group = "\${{ github.workflow }}-\${{ github.ref }}";
      cancelInProgress = true;
    };

    jobs.test = {
      runsOn = "ubuntu-latest";

      steps = [
        { uses = allowed-actions."actions/checkout".uses; }
        { uses = allowed-actions."cachix/install-nix-action".uses; }

        {
          name = "Run pre-commit hooks";
          shell = "nix develop .#standards --command bash {0}";
          run = "prek --from-ref $GITHUB_BASE_REF --to-ref $GITHUB_HEAD_REF --show-diff-on-failure";
        }
      ];
    };
  };
}
