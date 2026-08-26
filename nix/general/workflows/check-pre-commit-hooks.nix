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
    options.famedly.standards.ci.preCommit.setupSteps = lib.mkOption {
      description = ''
        Steps to run in the pre-commit job before the hooks themselves.

        Some hooks need more of the project than its files: a formatter that
        reads the language version out of a resolved package config formats
        differently when it cannot find one, which is how this job and a
        developer's machine come to disagree about the very files the job is
        checking. A language module that has such a hook prepares for it
        here.

        Kept apart from the hooks so that whatever they need is set up once
        for all of them, in the order the job runs.
      '';

      type = lib.types.listOf lib.types.attrs;
      default = [ ];
    };
  });

  config.perSystem = { config, ... }: {
    githubActions.workflows.check-pre-commit-hooks = {
      name = "Make sure all pre-commit hooks pass";

      # The floor for every job here, so that one added later reads the
      # repository and nothing more until it says otherwise.
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

        steps =
          steps.setup
          ++ config.famedly.standards.ci.preCommit.setupSteps
          ++ [
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
  };
}
