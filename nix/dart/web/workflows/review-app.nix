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
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (standardsLib) script;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
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
                GitHub environment the deployments are recorded in. The
                cleanup keys off this, so a repository sharing a server with
                others only ever removes its own review apps.
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
  });

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

          # A review app's name has to be agreed on in three places: the host
          # it is deployed under, its directory on the server, and the pattern
          # the cleanup below reads a request number back out of. Only one of
          # the three would fail visibly if they drifted apart — the cleanup
          # would quietly stop matching and the directories would pile up.
          appName = pullRequest: "${cfg.projectName}-pr-${pullRequest}";

          reviewAppName = appName "\${{ github.event.number }}";

          qaAppName = "qa-${cfg.projectName}";

          url = name: "https://${name}.${cfg.server}";

          # We use no ssh-agent, since it wouldn't survive the step that
          # starts it, and no `StrictHostKeyChecking no`, which would hand the
          # key to whoever answers on that name.
          authorise = ''
            install -d -m 700 ~/.ssh
            printf '%s\n' "$SSH_PRIVATE_KEY" >${identity}
            chmod 600 ${identity}

            ssh-keyscan -t rsa,ecdsa,ed25519 ${cfg.server} >>~/.ssh/known_hosts
          '';

          ssh = "ssh -i ${identity} -o IdentitiesOnly=yes";

          target = directory: "${cfg.user}@${cfg.server}:${cfg.root}/${directory}";

          # We pass `--delete`, so that a file a build stopped producing stops
          # being served.
          deploy = directory: ''
            rsync -av --delete --rsh='${ssh}' site/ ${lib.escapeShellArg (target directory)}
          '';

          download = [
            {
              uses = allowed-actions."actions/download-artifact".uses;

              with_ = {
                name = projectConfig.web.artifact;
                path = "site";
              };
            }
          ];

          key.SSH_PRIVATE_KEY = "\${{ secrets.FRONTEND_REVIEW_APP_SSH_KEY }}";

          announce = ''
            echo "$NAME: $URL" >>"$GITHUB_STEP_SUMMARY"
          '';

          # The two deployments differ in when they run, what they are called
          # and which name they land under. Putting a build on the review
          # server is the same job for both.
          deployJob =
            {
              if_,
              step,
              label,
              app,
            }:
            {
              inherit if_;

              needs = [ "build" ];
              runsOn = "ubuntu-latest";

              timeoutMinutes = 15;

              environment = {
                name = cfg.environment;
                url = url app;
              };

              steps = download ++ [
                {
                  name = step;

                  # The address is announced from the environment rather than
                  # interpolated into the script, so the summary and the
                  # deployment record cannot disagree about where it went.
                  env = key // {
                    NAME = label;
                    URL = url app;
                  };

                  run = script [
                    authorise
                    (deploy app)
                    announce
                  ];
                }
              ];
            };
        in
        {
          review-app = deployJob {
            # Dependabot's pull requests have no access to the key.
            if_ = "github.event_name == 'pull_request' && github.actor != 'dependabot[bot]'";

            step = "Deploy the review app";
            label = "Review app";
            app = reviewAppName;
          };

          qa-app = deployJob {
            # A single shared slot for QA, so it follows release candidates.
            if_ = "github.event_name == 'push' && contains(github.ref_name, 'rc')";

            step = "Deploy the QA app";
            label = "QA app";
            app = qaAppName;
          };

          cleanup-review-apps = {
            # As above, Dependabot's requests have no access to the key.
            if_ = "github.event_name == 'pull_request' && github.actor != 'dependabot[bot]'";
            runsOn = "ubuntu-latest";

            timeoutMinutes = 15;

            # Retiring a deployment is a write, and the default token is not.
            permissions = {
              deployments = "write";
              pull-requests = "read";
            };

            steps = [
              {
                # The server has no idea when a request closes. We do this on
                # every run rather than on `pull_request: closed`, which
                # wouldn't fire for a request closed while CI was disabled,
                # and the directory would then stay forever.
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
                    	# We read this out of the published address rather than
                    	# the branch, since a branch can carry a second request
                    	# after the first closed.
                    	url="$(gh api \
                    		"/repos/$GITHUB_REPOSITORY/deployments/$deployment/statuses" \
                    		--jq 'map(.environment_url | select(. != null and . != "")) | .[0] // empty')"

                    	pr="$(printf '%s\n' "$url" \
                    		| sed -n 's|^${
                        # The address is a pattern here, so the dots in the
                        # server's name have to stop being wildcards. The
                        # name itself carries none.
                        lib.replaceStrings [ "." ] [ "\\." ] (url (appName ''\([0-9][0-9]*\)''))
                      }.*|\1|p')"

                    	# The QA app, deployed from a tag, answers to no request.
                    	test -n "$pr" || continue

                    	# An empty state, from a vanished request or a hiccup in
                    	# the API, is not an invitation to delete anything.
                    	state="$(gh api "/repos/$GITHUB_REPOSITORY/pulls/$pr" \
                    		--jq '.state // empty' 2>/dev/null || true)"

                    	test "$state" = closed || continue

                    	echo "Removing the review app of pull request $pr"

                    	${ssh} -n ${lib.escapeShellArg "${cfg.user}@${cfg.server}"} \
                    		rm -rf "${cfg.root}/${appName "$pr"}"

                    	# The deployment goes too, or the next run looks at it
                    	# again, and it can't be deleted while it is active.
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
        lib.nameValuePair projectConfig.web.workflowId { jobs = mkJobs project projectConfig; }
      ) projects;
    };
}
