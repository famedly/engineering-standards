{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.commitMessages = {
        enable = lib.mkEnableOption ''
          checking that every commit in a pull request describes itself in the
          conventional commits form

          Opt-in rather than on everywhere, because switching it on turns every
          open pull request whose history predates the rule red at once, and
          that is a decision for whoever maintains the repository
        '';

        types = lib.mkOption {
          description = ''
            Types a commit subject may declare itself as.
          '';

          type = lib.types.listOf (lib.types.strMatching "[a-z]+");

          default = [
            "build"
            "chore"
            "ci"
            "docs"
            "feat"
            "fix"
            "perf"
            "refactor"
            "revert"
            "style"
            "test"
          ];
        };
      };
    }
  );

  config.perSystem =
    { config, ... }:
    let
      cfg = config.famedly.standards.commitMessages;
    in
    lib.mkIf cfg.enable {
      githubActions.workflows.check-commit-messages = {
        name = "Make sure all commit messages are conventional";

        # The floor for every job here, so that one added later reads the
        # repository and nothing more until it says otherwise.
        permissions.contents = "read";

        # Like the pre-commit hooks, and for the same reason: on `push` there
        # is no telling where the series of commits under review starts.
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

        jobs.commit-messages = {
          runsOn = "ubuntu-latest";

          steps = [
            {
              uses = allowed-actions."actions/checkout".uses;

              # The base commit has to be there for the range below to resolve,
              # and a shallow clone does not carry it.
              with_.fetch-depth = 0;
            }

            {
              name = "Check the commit messages";

              env = {
                PATTERN = "^(${lib.concatStringsSep "|" cfg.types})(\\([^)]+\\))?!?: .+";
                BASE = "\${{ github.event.pull_request.base.sha }}";
                HEAD = "\${{ github.event.pull_request.head.sha }}";
              };

              # One commit per line, and every line read. The workflow this
              # replaces pulled the whole log into a single string and matched
              # it once, which anchored the pattern to the first subject and
              # let every later commit through unexamined.
              #
              # Merges are exempt: their subjects are written by whoever
              # pressed the button, not by us.
              run = ''
                failed=0

                while IFS= read -r subject; do
                  if [[ $subject =~ $PATTERN ]]; then
                    echo "ok:  $subject"
                  else
                    echo "::error::not a conventional commit subject: $subject"
                    failed=1
                  fi
                done < <(git log --no-merges --format=%s "$BASE..$HEAD")

                exit "$failed"
              '';
            }
          ];
        };
      };
    };
}
