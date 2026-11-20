## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  flake-parts-lib,
  standardsLib,
  ...
}:
let
  inherit (config.famedly.standards.ci) steps;
  inherit (standardsLib) script breakingChangeMarks;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.commitMessages = {
      enable = lib.mkEnableOption ''
        checking that every commit in a pull request describes itself in the
        conventional commits form, and that a breaking one carries both of its
        marks

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
  });

  config.perSystem =
    { config, ... }:
    let
      cfg = config.famedly.standards.commitMessages;
      inherit (config.famedly.standards.breakingChanges) enforce;
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

          steps =
            # The base commit has to be there for the range below to resolve,
            # and a shallow clone does not carry it.
            steps.withHistory steps.checkout ++ [
              {
                name = "Check the commit messages";

                env = {
                  PATTERN = "^(${lib.concatStringsSep "|" cfg.types})(\\([^)]+\\))?!?: .+";
                  LEVEL = if enforce then "error" else "warning";
                  BASE = "\${{ github.event.pull_request.base.sha }}";
                  HEAD = "\${{ github.event.pull_request.head.sha }}";
                };

                # One commit at a time, and every one read. The workflow this
                # replaces pulled the whole log into a single string and matched
                # it once, which anchored the pattern to the first subject and
                # let every later commit through unexamined.
                #
                # Merges are exempt: their subjects are written by whoever
                # pressed the button, not by us.
                run = script [
                  breakingChangeMarks
                  ''
                    failed=0

                    for commit in $(git rev-list --no-merges "$BASE..$HEAD"); do
                      subject=$(git show -s --format=%s "$commit")
                      body=$(git show -s --format=%b "$commit")

                      if ! [[ $subject =~ $PATTERN ]]; then
                        echo "::error::not a conventional commit subject: $subject"
                        failed=1
                        continue
                      fi

                      # A breaking change needs both marks, anything else neither.
                      bang=no
                      footer=no
                      has_bang "$subject" && bang=yes
                      has_footer "$body" && footer=yes

                      if [[ $bang == "$footer" ]]; then
                        echo "ok:  $subject"
                      else
                        echo "::$LEVEL::a breaking change needs both a ! before the colon and a BREAKING CHANGE: footer: $subject"
                        if [[ $LEVEL == error ]]; then
                          failed=1
                        fi
                      fi
                    done

                    exit "$failed"
                  ''
                ];
              }
            ];
        };
      };
    };
}
