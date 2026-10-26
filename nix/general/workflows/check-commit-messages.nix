## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (config.famedly.standards.ci) steps;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
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

          Each one becomes a section of the release notes, see
          `famedly.standards.changelog`.
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
          "update"
        ];
      };
    };
  });

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

          steps =
            # The base commit has to be there for the range below to resolve,
            # and a shallow clone does not carry it.
            steps.withHistory steps.setup ++ [
              {
                name = "Check the commit messages";

                # The same command the pre-push hook runs, so that a push that
                # got past it locally gets past this too.
                shell = steps.devshell;

                env = {
                  BASE = "\${{ github.event.pull_request.base.sha }}";
                  HEAD = "\${{ github.event.pull_request.head.sha }}";
                };

                run = ''check-commits "$BASE..$HEAD"'';
              }
            ];
        };
      };
    };
}
