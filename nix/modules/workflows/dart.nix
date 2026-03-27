# Dart workflow module: generates complete Dart/Flutter CI and publishing workflows.
#
# Generated files in consumer repo:
#   .github/workflows/dart-ci.yml       — full Dart/Flutter CI pipeline
#   .github/workflows/publish-pub.yml   — publish to pub.dev
#   .github/workflows/review-app.yml    — deploy review app
#   .github/actions/dart-prepare/action.yml — SSH setup for private deps

{ flake-parts-lib, lib, ... }:
let
  root = ../../..;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.workflows;
      av = config.famedly.standards.actionVersions;

      ciConcurrency = {
        group = "\${{ github.workflow }}-\${{ github.ref }}";
        cancelInProgress = true;
      };

      dartPrepareAction = "${root}/.github/actions/dart-prepare/action.yml";
    in
    {
      options.famedly.standards.workflows = {
        dartCi = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate Dart/Flutter CI workflow.";
          };

          envFile = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Path to .env file for version overrides.";
          };

          directory = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Subdirectory for the dart project.";
          };

          ignoreFormatting = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Subdirectory to auto-format before the format check (e.g. lib/l10n/).";
          };
        };

        dartPublish = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate pub.dev publish workflow.";
          };

          envFile = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Path to .env file for version overrides.";
          };
        };

        dartReviewApp = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate review app deployment workflow.";
          };

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
      };

      config = {
        githubActions.workflows = lib.mkMerge [
          (lib.mkIf cfg.dartCi.enable {
            dart-ci = {
              name = "Dart CI";
              on = {
                push.branches = [ "main" ];
                pullRequest = {
                  branches = [ "**" ];
                  types = [
                    "opened"
                    "reopened"
                    "synchronize"
                    "ready_for_review"
                  ];
                };
                mergeGroup = { };
              };
              permissions = {
                contents = "read";
              };
              concurrency = ciConcurrency;
              jobs.dart_ci = lib.mkMerge [
                (lib.mkIf (cfg.dartCi.envFile != "") {
                  env.env_file = cfg.dartCi.envFile;
                })
                {
                  runsOn = "ubuntu-latest";
                  steps = [
                    { uses = "actions/checkout@${av.checkout}"; }
                  ]

                  ++ lib.optionals (cfg.dartCi.envFile != "") [
                    {
                      name = "Read env file";
                      if_ = "env.env_file != ''";
                      run = "cat \${{ env.env_file }} >> $GITHUB_ENV";
                    }
                  ]

                  ++ [
                    {
                      uses = "dart-lang/setup-dart@${av.setupDart}";
                      if_ = "env.dart_version != ''";
                      with_ = {
                        sdk = "\${{ env.dart_version }}";
                      };
                    }
                    {
                      uses = "subosito/flutter-action@${av.flutterAction}";
                      with_ = {
                        flutter-version = "\${{ env.flutter_version }}";
                        cache = true;
                      };
                    }
                    {
                      uses = "actions/cache@${av.cache}";
                      with_ = {
                        path = "~/.pub-cache";
                        key = "\${{ runner.os }}-pub-\${{ hashFiles('**/pubspec.lock') }}";
                      };
                    }
                    {
                      name = "Set up private deps";
                      uses = "./.github/actions/dart-prepare";
                      with_ = {
                        ssh_key = "\${{ secrets.ssh_key }}";
                        container_mode = "false";
                      };
                    }
                  ]

                  ++ [
                    {
                      name = "Install dependencies";
                      workingDirectory = if cfg.dartCi.directory != "" then cfg.dartCi.directory else null;
                      run = "flutter pub get";
                    }
                    {
                      name = "Check pubspec.lock is up to date";
                      run = "git check-ignore -q pubspec.lock || git diff --exit-code pubspec.lock";
                    }
                  ]

                  ++ lib.optionals (cfg.dartCi.ignoreFormatting != "") [
                    {
                      run = "dart format ${cfg.dartCi.ignoreFormatting}";
                    }
                  ]

                  ++ [
                    {
                      name = "Check formatting";
                      workingDirectory = if cfg.dartCi.directory != "" then cfg.dartCi.directory else null;
                      run = ''
                        dart format lib/ --set-exit-if-changed || {
                          {
                            echo '```diff'
                            git diff
                            echo '```'
                          } >> "$GITHUB_STEP_SUMMARY"
                          exit 1
                        }
                      '';
                    }
                    {
                      name = "Run analyzer";
                      workingDirectory = if cfg.dartCi.directory != "" then cfg.dartCi.directory else null;
                      run = ''
                        SCRIPT=$(cat << 'EOL'
                        import json,sys,os

                        obj = json.load(sys.stdin)
                        diagnostics = obj["diagnostics"]

                        if diagnostics:
                            print('|severity|file|problem|suggestion|documentation|')
                            print('|:--|:--|:--|:--|:--|')
                        else:
                            exit(0)

                        sha = os.environ["GITHUB_SHA"]
                        server = os.environ["GITHUB_SERVER_URL"]
                        repo = os.environ["GITHUB_REPOSITORY"]
                        workspace = os.environ["GITHUB_WORKSPACE"]

                        for d in diagnostics:
                            l = d["location"]
                            file = l["file"].removeprefix(workspace + "/")
                            start = str(l["range"]["start"]["line"])
                            end = str(l["range"]["end"]["line"])
                            location = f'[{file}:{start}]({server}/{repo}/blob/{sha}/{file}#L{start}-L{end})'
                            print("", d["severity"], location, d.get("correctionMessage", "").replace("|", "\\|"), d.get("correctionMessage", "").replace("|", "\\|"), f'[{d["code"]}]({d.get("documentation", "")})', "", sep="| ")
                        exit(1)
                        EOL
                        )
                        dart analyze --format=json | python3 -c "$SCRIPT" | tee -a "$GITHUB_STEP_SUMMARY"
                        test ''${PIPESTATUS[0]} -eq 0 -a ''${PIPESTATUS[1]} -eq 0 -a ''${PIPESTATUS[2]} -eq 0
                      '';
                    }
                    {
                      name = "Sort imports";
                      workingDirectory = if cfg.dartCi.directory != "" then cfg.dartCi.directory else null;
                      run = ''
                        if ! dart run import_sorter:main --no-comments --exit-if-changed; then
                          dart run import_sorter:main --no-comments
                          {
                            echo '```diff'
                            git diff
                            echo '```'
                          } >> "$GITHUB_STEP_SUMMARY"
                          exit 1
                        fi
                      '';
                    }
                    {
                      name = "Check for commented-out code";
                      run = ''
                        if grep -R --include="*.dart" -nE '^[[:space:]]*//[^/<].*;[[:space:]]*$' lib/; then
                          echo "❌ Found commented-out Dart code ending with semicolon."
                          exit 1
                        fi
                      '';
                    }
                    {
                      name = "Check unused dependencies";
                      run = ''
                        dart pub global activate dependency_validator
                        dart pub global run dependency_validator
                      '';
                    }
                    {
                      id = "check_linter";
                      name = "dart_code_linter — analyze";
                      continueOnError = true;
                      workingDirectory = if cfg.dartCi.directory != "" then cfg.dartCi.directory else null;
                      run = ''
                        if grep -q 'dart_code_linter:' pubspec.yaml; then
                          dart run dart_code_linter:metrics analyze lib --reporter=github
                        else
                          echo "::notice::dart_code_linter not in pubspec.yaml — skipping"
                        fi
                      '';
                    }
                    {
                      name = "dart_code_linter — unused files";
                      if_ = "steps.check_linter.outcome == 'success'";
                      run = "dart run dart_code_linter:metrics check-unused-files lib";
                    }
                    {
                      name = "dart_code_linter — unused code";
                      if_ = "steps.check_linter.outcome == 'success'";
                      run = ''dart run dart_code_linter:metrics check-unused-code lib --exclude="{**/generated/**.dart,**.g.dart,**.freezed.dart}"'';
                    }
                    {
                      name = "Check unused translations";
                      workingDirectory = if cfg.dartCi.directory != "" then cfg.dartCi.directory else null;
                      continueOnError = true;
                      run = ''
                        if grep -q 'translations_cleaner:' pubspec.yaml; then
                          rm -f lib/l10n/l10n*.dart
                          flutter pub run translations_cleaner list-unused-terms -a
                        fi
                      '';
                    }
                  ];
                }
              ];
            };
          })

          (lib.mkIf cfg.dartPublish.enable {
            publish-pub = {
              name = "Publish to pub.dev";
              on.push.tags = [ "v*" ];
              jobs.publish = {
                runsOn = "ubuntu-latest";
                environment = "pub.dev";
                permissions = {
                  id-token = "write";
                };
                steps = [
                  { uses = "actions/checkout@${av.checkout}"; }
                ]

                ++ lib.optionals (cfg.dartPublish.envFile != "") [
                  {
                    name = "Read env file";
                    run = "cat ${cfg.dartPublish.envFile} >> $GITHUB_ENV";
                  }
                ]

                ++ [
                  {
                    uses = "dart-lang/setup-dart@${av.setupDart}";
                    with_ = {
                      sdk = "\${{ env.dart_version || 'stable' }}";
                    };
                  }
                  { run = "dart pub get"; }
                  { run = "dart pub publish --dry-run"; }
                  { run = "dart pub publish -f"; }
                ];
              };
            };
          })

          (lib.mkIf cfg.dartReviewApp.enable {
            review-app = {
              name = "Deploy review app";
              on.pullRequest = {
                types = [
                  "opened"
                  "reopened"
                  "synchronize"
                  "closed"
                ];
              };
              permissions = {
                contents = "read";
                deployments = "write";
              };
              jobs = {
                deploy_review_app = {
                  if_ = "\${{ github.event.pull_request.number }}";
                  runsOn = "ubuntu-latest";
                  environment = {
                    name = cfg.dartReviewApp.environment;
                    url = "https://${cfg.dartReviewApp.projectName}-pr-\${{ github.event.pull_request.number }}.web-review.famedly.de";
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
                        echo "''${{ secrets.FRONTEND_REVIEW_APP_SSH_KEY }}" | ssh-add -
                        mkdir -p ~/.ssh
                        echo -e "Host *\n\tStrictHostKeyChecking no\n" > ~/.ssh/config
                        rsync -av --delete public/ \
                          "web-review@web-review.famedly.de:/opt/web-review/web/${cfg.dartReviewApp.projectName}-pr-''${{ github.event.pull_request.number }}"
                        echo "Review app: [App](https://${cfg.dartReviewApp.projectName}-pr-''${{ github.event.pull_request.number }}.web-review.famedly.de)" >> "$GITHUB_STEP_SUMMARY"
                      '';
                    }
                  ];
                };

                cleanup_review_apps = {
                  runsOn = "ubuntu-latest";
                  steps = [
                    {
                      name = "Clean up closed PR deployments";
                      env = {
                        GITHUB_TOKEN = "\${{ secrets.GITHUB_TOKEN }}";
                      };
                      run = ''
                        eval $(ssh-agent -s)
                        echo "''${{ secrets.FRONTEND_REVIEW_APP_SSH_KEY }}" | ssh-add -
                        mkdir -p ~/.ssh
                        echo -e "Host *\n\tStrictHostKeyChecking no\n" > ~/.ssh/config

                        gh api -H "Accept: application/vnd.github+json" \
                          "/repos/''${{ github.repository }}/deployments?environment=${cfg.dartReviewApp.environment}" \
                          | jq -c 'group_by(.ref) | map({ref: .[0].ref, deployments: map(.id) | join(" ")}) | .[]' > ./deployments

                        while IFS= read -r deployment; do
                          ref=$(echo "$deployment" | jq -r '.ref')
                          gh api --paginate -X GET -H "Accept: application/vnd.github+json" \
                            "/repos/''${{ github.repository }}/pulls" -f "head=famedly:$ref" -f "state=closed" \
                            | jq '.[].number' > ./prs

                          while IFS= read -r pr; do
                            echo "Deleting review app for PR $pr"
                            ssh -n web-review@web-review.famedly.de rm -rf \
                              "/opt/web-review/web/${cfg.dartReviewApp.projectName}-pr-''${pr}"
                          done < ./prs

                          if [ -s ./prs ]; then
                            for d in $(echo "$deployment" | jq -r '.deployments'); do
                              gh api --method POST -H "Accept: application/vnd.github+json" \
                                "/repos/''${{ github.repository }}/deployments/''${d}/statuses" -f state='inactive'
                              gh api --method DELETE -H "Accept: application/vnd.github+json" \
                                "/repos/''${{ github.repository }}/deployments/''${d}"
                            done
                          fi
                        done < ./deployments
                      '';
                    }
                  ];
                };
              };
            };
          })
        ];

        famedly.standards._internal.managedFiles =
          lib.optionals cfg.dartCi.enable [
            {
              src = config.githubActions.workflowFiles."dart-ci.yml";
              dest = ".github/workflows/dart-ci.yml";
            }
            {
              src = dartPrepareAction;
              dest = ".github/actions/dart-prepare/action.yml";
            }
          ]
          ++ lib.optionals cfg.dartPublish.enable [
            {
              src = config.githubActions.workflowFiles."publish-pub.yml";
              dest = ".github/workflows/publish-pub.yml";
            }
          ]
          ++ lib.optionals cfg.dartReviewApp.enable [
            {
              src = config.githubActions.workflowFiles."review-app.yml";
              dest = ".github/workflows/review-app.yml";
            }
          ];
      };
    }
  );
}
