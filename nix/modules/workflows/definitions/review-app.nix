{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghExpr ghSecret;
  isWorkflowRun = config.triggerMode == "workflowRun";
  prNumber =
    if isWorkflowRun then
      ghExpr "github.event.workflow_run.pull_requests[0].number"
    else
      ghExpr "github.event.pull_request.number";
in
{
  options = {
    projectName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Project name used in the review app URL.";
    };
    environment = lib.mkOption {
      type = lib.types.str;
      default = "review";
      description = "GitHub environment name for the deployment.";
    };
    triggerMode = lib.mkOption {
      type = lib.types.enum [
        "pullRequest"
        "workflowRun"
      ];
      default = "pullRequest";
      description = ''
        How the review app deployment is triggered.
        "pullRequest" (default) runs on PR events directly.
        "workflowRun" runs after an upstream workflow completes,
        with a separate pull_request trigger for cleanup.
      '';
    };
    triggerWorkflow = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Name of the upstream workflow (only used with workflowRun trigger mode).";
    };
    artifactName = lib.mkOption {
      type = lib.types.str;
      default = "web";
      description = "Name of the build artifact to deploy.";
    };
  };

  config.definition = {
    name = "Deploy review app";
    on =
      if isWorkflowRun then
        {
          workflowRun = {
            workflows = [ config.triggerWorkflow ];
            types = [ "completed" ];
          };
          pullRequest.types = [ "closed" ];
        }
      else
        {
          pullRequest.types = [
            "opened"
            "reopened"
            "synchronize"
            "closed"
          ];
        };
    permissions = {
      contents = "read";
      deployments = "write";
      actions = "read";
    };
    jobs = {
      deploy_review_app = {
        if_ =
          if isWorkflowRun then
            "github.event_name == 'workflow_run' && github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.pull_requests[0]"
          else
            ghExpr "github.event.pull_request.number";
        runsOn = "ubuntu-latest";
        environment = {
          name = config.environment;
          url = "https://${config.projectName}-pr-${prNumber}.web-review.famedly.de";
        };
        steps = [
          (
            {
              uses = "actions/download-artifact@${av.downloadArtifact}";
              with_ =
                {
                  name = config.artifactName;
                  path = "public";
                }
                // lib.optionalAttrs isWorkflowRun {
                  run-id = ghExpr "github.event.workflow_run.run_id";
                  github-token = ghSecret "GITHUB_TOKEN";
                };
            }
          )
          {
            name = "Deploy to review server";
            run = ''
              eval $(ssh-agent -s)
              echo "${ghSecret "FRONTEND_REVIEW_APP_SSH_KEY"}" | ssh-add -
              mkdir -p ~/.ssh
              echo -e "Host *\n\tStrictHostKeyChecking no\n" > ~/.ssh/config
              rsync -av --delete public/ \
                "web-review@web-review.famedly.de:/opt/web-review/web/${config.projectName}-pr-${prNumber}"
              echo "Review app: [App](https://${config.projectName}-pr-${prNumber}.web-review.famedly.de)" >> "$GITHUB_STEP_SUMMARY"
            '';
          }
        ];
      };

      cleanup_review_apps = {
        runsOn = "ubuntu-latest";
        if_ =
          if isWorkflowRun then "github.event_name == 'pull_request'" else null;
        steps = [
          {
            name = "Clean up closed PR deployments";
            env.GITHUB_TOKEN = ghSecret "GITHUB_TOKEN";
            run = ''
              eval $(ssh-agent -s)
              echo "${ghSecret "FRONTEND_REVIEW_APP_SSH_KEY"}" | ssh-add -
              mkdir -p ~/.ssh
              echo -e "Host *\n\tStrictHostKeyChecking no\n" > ~/.ssh/config

              gh api -H "Accept: application/vnd.github+json" \
                "/repos/${ghExpr "github.repository"}/deployments?environment=${config.environment}" \
                | jq -c 'group_by(.ref) | map({ref: .[0].ref, deployments: map(.id) | join(" ")}) | .[]' > ./deployments

              while IFS= read -r deployment; do
                ref=$(echo "$deployment" | jq -r '.ref')
                gh api --paginate -X GET -H "Accept: application/vnd.github+json" \
                  "/repos/${ghExpr "github.repository"}/pulls" -f "head=famedly:$ref" -f "state=closed" \
                  | jq '.[].number' > ./prs

                while IFS= read -r pr; do
                  echo "Deleting review app for PR $pr"
                  ssh -n web-review@web-review.famedly.de rm -rf \
                    "/opt/web-review/web/${config.projectName}-pr-''${pr}"
                done < ./prs

                if [ -s ./prs ]; then
                  for d in $(echo "$deployment" | jq -r '.deployments'); do
                    gh api --method POST -H "Accept: application/vnd.github+json" \
                      "/repos/${ghExpr "github.repository"}/deployments/''${d}/statuses" -f state='inactive'
                    gh api --method DELETE -H "Accept: application/vnd.github+json" \
                      "/repos/${ghExpr "github.repository"}/deployments/''${d}"
                  done
                fi
              done < ./deployments
            '';
          }
        ];
      };
    };
  };
}
