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
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (import ../workflow-ids.nix { inherit lib; }) artifact workflowId;

  script = import ../../../lib/compose-script.nix { inherit lib; };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.web.reviewApp = {
              enable = lib.mkEnableOption "deploying this site for review while a pull request is open";

              projectName = lib.mkOption {
                description = ''
                  Name the review app is addressed by, used both in its
                  hostname and in its directory on the review server.
                '';
                type = lib.types.str;
                example = "famedly-control";
              };

              environment = lib.mkOption {
                description = ''
                  GitHub environment the deployments are recorded in.

                  Cleaning up after closed pull requests keys off this, so a
                  repository that shares a server with others still only ever
                  removes its own review apps.
                '';
                type = lib.types.str;
                default = "review";
              };

              server = lib.mkOption {
                description = ''
                  Host that serves the review apps, and the domain their
                  hostnames are formed under.
                '';
                type = lib.types.str;
                default = "web-review.famedly.de";
              };

              user = lib.mkOption {
                description = "User to reach the review server as.";
                type = lib.types.str;
                default = "web-review";
              };

              root = lib.mkOption {
                description = "Directory the review server serves from.";
                type = lib.types.strMatching "/.+";
                default = "/opt/web-review/web";
              };
            };
          }
        );
      };
    }
  );

  config.perSystem =
    { config, ... }:
    let
      projects = lib.filterAttrs (
        _: project: project.web.enable && project.web.reviewApp.enable
      ) config.famedly.standards.dart.projects;

      mkJobs =
        project: projectConfig:
        let
          cfg = projectConfig.web.reviewApp;

          identity = "~/.ssh/review-app";

          reviewAppName = "${cfg.projectName}-pr-\${{ github.event.number }}";

          qaAppName = "qa-${cfg.projectName}";

          # Neither an ssh-agent nor `StrictHostKeyChecking no`, both of which
          # the workflow this replaces used: an agent does not survive the step
          # that starts it, and accepting any host key hands the deployment —
          # and the key that performs it — to whoever answers on that name.
          authorise = ''
            install -d -m 700 ~/.ssh
            printf '%s\n' "$SSH_PRIVATE_KEY" >${identity}
            chmod 600 ${identity}

            ssh-keyscan -t rsa,ecdsa,ed25519 ${cfg.server} >>~/.ssh/known_hosts
          '';

          ssh = "ssh -i ${identity} -o IdentitiesOnly=yes";

          target = directory: "${cfg.user}@${cfg.server}:${cfg.root}/${directory}";

          # `--delete`, so a file that a build stopped producing stops being
          # served instead of lingering from an earlier push to the same branch.
          deploy = directory: ''
            rsync -av --delete --rsh='${ssh}' site/ ${lib.escapeShellArg (target directory)}
          '';

          download = [
            {
              uses = allowed-actions."actions/download-artifact".uses;

              with_ = {
                name = artifact project;
                path = "site";
              };
            }
          ];

          key.SSH_PRIVATE_KEY = "\${{ secrets.FRONTEND_REVIEW_APP_SSH_KEY }}";

          announce = ''
            echo "$NAME: $URL" >>"$GITHUB_STEP_SUMMARY"
          '';
        in
        {
          review-app = {
            # Dependabot's pull requests run without access to our secrets, so
            # this could only ever fail for them.
            if_ = "github.event_name == 'pull_request' && github.actor != 'dependabot[bot]'";
            needs = [ "build" ];
            runsOn = "ubuntu-latest";

            timeoutMinutes = 15;

            environment = {
              name = cfg.environment;
              url = "https://${reviewAppName}.${cfg.server}";
            };

            steps = download ++ [
              {
                name = "Deploy the review app";

                env = key // {
                  NAME = "Review app";
                  URL = "https://${reviewAppName}.${cfg.server}";
                };

                run = script [
                  authorise
                  (deploy reviewAppName)
                  announce
                ];
              }
            ];
          };

          qa-app = {
            # Release candidates only. This deployment is a single shared slot
            # that QA looks at, so it follows the tags that ask for a look.
            if_ = "github.event_name == 'push' && contains(github.ref_name, 'rc')";
            needs = [ "build" ];
            runsOn = "ubuntu-latest";

            timeoutMinutes = 15;

            environment = {
              name = cfg.environment;
              url = "https://${qaAppName}.${cfg.server}";
            };

            steps = download ++ [
              {
                name = "Deploy the QA app";

                env = key // {
                  NAME = "QA app";
                  URL = "https://${qaAppName}.${cfg.server}";
                };

                run = script [
                  authorise
                  (deploy qaAppName)
                  announce
                ];
              }
            ];
          };

          cleanup-review-apps = {
            # Dependabot's requests run without our secrets, so this job would
            # have neither the key that reaches the server nor a token that may
            # write deployments — the same reason the deployment above skips
            # them.
            if_ = "github.event_name == 'pull_request' && github.actor != 'dependabot[bot]'";
            runsOn = "ubuntu-latest";

            timeoutMinutes = 15;

            # The default token may read a repository and nothing else, and
            # retiring a deployment is a write.
            permissions = {
              deployments = "write";
              pull-requests = "read";
            };

            steps = [
              {
                # The review server has no idea when a pull request closes, so
                # somebody has to tell it. Doing that here, on every run, keeps
                # it to one place — a workflow triggered by `pull_request:
                # closed` would not fire for a request closed while CI was
                # disabled, and the directory would then stay forever.
                name = "Remove the review apps of closed pull requests";

                env = key // {
                  GH_TOKEN = "\${{ secrets.GITHUB_TOKEN }}";
                  ENVIRONMENT = cfg.environment;
                };

                run = script [
                  authorise
                  ''
                    gh api --paginate \
                    	"/repos/$GITHUB_REPOSITORY/deployments?environment=$ENVIRONMENT" \
                    	--jq '.[].id' >deployments

                    while read -r deployment; do
                    	# Which request a deployment belongs to is read out of the
                    	# address it published, not out of its branch: a branch can
                    	# carry a second request after the first one closed, and the
                    	# closed one would then answer for the open one's deployment.
                    	url="$(gh api \
                    		"/repos/$GITHUB_REPOSITORY/deployments/$deployment/statuses" \
                    		--jq 'map(.environment_url | select(. != null and . != "")) | .[0] // empty')"

                    	pr="$(printf '%s\n' "$url" \
                    		| sed -n 's|^https://${cfg.projectName}-pr-\([0-9][0-9]*\)\..*|\1|p')"

                    	# The QA app, deployed from a tag, answers to no request.
                    	test -n "$pr" || continue

                    	# A request that no longer answers, or an interlude in
                    	# the API, leaves the state empty — and an empty state is
                    	# not an invitation to delete anything.
                    	state="$(gh api "/repos/$GITHUB_REPOSITORY/pulls/$pr" \
                    		--jq '.state // empty' 2>/dev/null || true)"

                    	test "$state" = closed || continue

                    	echo "Removing the review app of pull request $pr"

                    	${ssh} -n ${lib.escapeShellArg "${cfg.user}@${cfg.server}"} \
                    		rm -rf "${cfg.root}/${cfg.projectName}-pr-$pr"

                    	# The deployment goes too, or the next run would look at
                    	# it again — and it cannot be deleted while it counts as
                    	# active.
                    	gh api --method POST \
                    		"/repos/$GITHUB_REPOSITORY/deployments/$deployment/statuses" \
                    		-f state=inactive >/dev/null

                    	gh api --method DELETE \
                    		"/repos/$GITHUB_REPOSITORY/deployments/$deployment"
                    done <deployments
                  ''
                ];
              }
            ];
          };
        };
    in
    {
      githubActions.workflows = lib.mapAttrs' (
        project: projectConfig:
        lib.nameValuePair (workflowId project) { jobs = mkJobs project projectConfig; }
      ) projects;
    };
}
