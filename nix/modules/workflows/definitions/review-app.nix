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
  };

  config.definition = {
    name = "Deploy review app";
    on.pullRequest.types = [
      "opened"
      "reopened"
      "synchronize"
      "closed"
    ];
    permissions = {
      contents = "read";
      deployments = "write";
    };
    jobs = {
      deploy_review_app = {
        if_ = ghExpr "github.event.pull_request.number";
        runsOn = "ubuntu-latest";
        environment = {
          name = config.environment;
          url = "https://${config.projectName}-pr-${ghExpr "github.event.pull_request.number"}.web-review.famedly.de";
        };
        steps = [
          {
            uses = "actions/download-artifact@${av.downloadArtifact}";
            with_ = {
              name = "web";
              path = "public";
            };
          }
          {
            name = "Deploy to review server";
            run = ''
              eval $(ssh-agent -s)
              echo "${ghSecret "FRONTEND_REVIEW_APP_SSH_KEY"}" | ssh-add -
              mkdir -p ~/.ssh
              echo -e "Host *\n\tStrictHostKeyChecking no\n" > ~/.ssh/config
              rsync -av --delete public/ \
                "web-review@web-review.famedly.de:/opt/web-review/web/${config.projectName}-pr-${ghExpr "github.event.pull_request.number"}"
              echo "Review app: [App](https://${config.projectName}-pr-${ghExpr "github.event.pull_request.number"}.web-review.famedly.de)" >> "$GITHUB_STEP_SUMMARY"
            '';
          }
        ];
      };

      cleanup_review_apps = {
        runsOn = "ubuntu-latest";
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
