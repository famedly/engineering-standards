# General workflow module: generates complete workflows for shared checks.
#
# Generated files in consumer repo:
#   .github/workflows/general-checks.yml          — conventional commit validation
#   .github/workflows/authenticate-commits.yml     — OpenPGP commit authentication
#   .github/workflows/add-to-project.yml           — auto-add issues to project board
#   .github/workflows/update-openpgp-policy.yml    — regenerate openpgp-policy.toml
#   .github/workflows/fast-forward.yml             — fast-forward merge via PR comment
#   .github/workflows/ai-review.yml               — AI code review with Claude
#   .github/workflows/release.yml                  — GitHub Release on tag push
#   .github/workflows/reuse.yml                    — REUSE/SPDX license compliance

{ flake-parts-lib, lib, ... }:
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

      prConcurrency = {
        group = "\${{ github.workflow }}-\${{ github.ref }}";
        cancelInProgress = true;
      };
    in
    {
      options.famedly.standards.workflows = {
        conventionalCommits = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate workflow for conventional commit validation on PRs.";
        };

        authenticateCommits = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate workflow for OpenPGP commit authentication.";
        };

        fastForward = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate workflow for fast-forward merges via /fast-forward PR comment.";
        };

        addToProject = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate workflow to auto-add issues to a GitHub project.";
          };

          projectUrl = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "URL of the GitHub project board.";
            example = "https://github.com/orgs/famedly/projects/42";
          };
        };

        updateOpenpgpPolicy = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate workflow to regenerate openpgp-policy.toml.";
          };

          teams = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Teams input for the OpenPGP policy workflow (JSON array).";
            example = ''["backend", "frontend"]'';
          };
        };

        aiReview = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate AI code review workflow using anthropics/claude-code-action on PRs.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = "claude-sonnet-4-5";
            description = "Claude model to use for the review.";
            example = "claude-opus-4-5";
          };
        };

        release = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate GitHub Release workflow triggered on version tag pushes.";
          };

          draft = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Create releases as drafts instead of publishing immediately.";
          };
        };

        reuse = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate REUSE/SPDX license compliance check workflow on PRs.";
        };
      };

      config = {
        githubActions.workflows = lib.mkMerge [
          (lib.mkIf cfg.conventionalCommits {
            general-checks = {
              name = "General checks (conventional commits)";
              on.pullRequest = { };
              permissions = {
                contents = "read";
              };
              concurrency = prConcurrency;
              jobs.conventional_commits = {
                runsOn = "ubuntu-latest";
                if_ = "github.ref != 'refs/heads/main' && github.event.pull_request";
                steps = [
                  {
                    uses = "actions/checkout@${av.checkout}";
                    with_ = {
                      fetch-depth = 0;
                    };
                  }
                  {
                    name = "Check conventional commits";
                    run = ''
                      COMMIT_MSGS=$(git log --no-merges --format=%s origin/main..HEAD)
                      FAILED=0
                      while IFS= read -r msg; do
                        if [[ ! "$msg" =~ ^(ci|feat|fix|docs|style|refactor|perf|test|chore|build|revert)(\(.+\))?:\ .+ ]]; then
                          echo "::error::Invalid commit message: $msg"
                          FAILED=1
                        fi
                      done <<< "$COMMIT_MSGS"
                      exit $FAILED
                    '';
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.authenticateCommits {
            authenticate-commits = {
              name = "Authenticate commits";
              on.pullRequest = { };
              jobs.authenticate-commits = {
                runsOn = "ubuntu-latest";
                permissions = {
                  contents = "read";
                  pull-requests = "write";
                  issues = "write";
                };
                steps = [
                  {
                    name = "Authenticating commits";
                    uses = "sequoia-pgp/authenticate-commits@${av.authenticateCommits}";
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.fastForward {
            fast-forward = {
              name = "Fast-forward merge";
              on.issueComment = {
                types = [ "created" ];
              };
              permissions = {
                contents = "write";
                pull-requests = "write";
              };
              jobs.fast-forward = {
                runsOn = "ubuntu-latest";
                if_ = "github.event.issue.pull_request && contains(github.event.comment.body, '/fast-forward')";
                steps = [
                  {
                    uses = "sequoia-pgp/fast-forward@${av.fastForward}";
                    with_ = {
                      merge = true;
                    };
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.addToProject.enable {
            add-to-project = {
              name = "Add Issue to Project";
              on.issues = {
                types = [ "opened" ];
              };
              jobs.add-to-project = {
                name = "Add issue to project";
                runsOn = "ubuntu-latest";
                steps = [
                  {
                    uses = "actions/add-to-project@${av.addToProject}";
                    with_ = {
                      project-url = cfg.addToProject.projectUrl;
                      github-token = "\${{ secrets.ADD_ISSUE_TO_PROJECT_PAT }}";
                    };
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.updateOpenpgpPolicy.enable {
            update-openpgp-policy = {
              name = "Regenerate OpenPGP Policy";
              on = {
                schedule = [
                  { cron = "0 6 * * 1"; }
                ];
                workflowDispatch = { };
              };
              jobs.regenerate-policy = {
                runsOn = "ubuntu-latest";
                permissions = {
                  contents = "read";
                  pull-requests = "write";
                };
                steps = [
                  {
                    uses = "actions/checkout@${av.checkout}";
                    with_ = {
                      repository = "famedly/openpgp-policy";
                      token = "\${{ github.token }}";
                      sparse-checkout = "openpgp-policy.toml\nusers.yml";
                    };
                  }
                  {
                    uses = "hustcer/setup-nu@${av.setupNu}";
                    with_ = {
                      version = "0.94.2";
                    };
                  }
                  {
                    name = "Generate Policy";
                    shell = "nu {0}";
                    run = ''
                      rm openpgp-policy.toml
                      let users = open users.yml | get users | transpose email fingerprint
                      $users | par-each {|user| sq wkd get $user.email }
                      let role_overrides = open users.yml | get teams | transpose team users | filter {|it| $it.team in ${cfg.updateOpenpgpPolicy.teams} } | get users | reduce {|it, acc| $acc | merge $it }
                      $users | each {|user|
                      	if ($role_overrides | get -i $user.email) == null {
                      		sq-git policy authorize --committer $user.email $user.fingerprint
                      	} else if ($role_overrides | get -i $user.email) == "project-maintainer" {
                      		sq-git policy authorize --project-maintainer $user.email $user.fingerprint
                      	} else if ($role_overrides | get -i $user.email) == "release-manager" {
                      		sq-git policy authorize --release-manager $user.email $user.fingerprint
                      	}
                      }
                      echo "Successfully regenerated openpgp-policy.toml"
                    '';
                  }
                  {
                    name = "Diff Policy";
                    run = ''
                      echo "POLICY_CHANGED=$(git diff --exit-code openpgp-policy.toml && echo true || echo false )" >> $GITHUB_ENV
                    '';
                  }
                  {
                    name = "Commit and create pull request";
                    if_ = "env.POLICY_CHANGED == 'true'";
                    env = {
                      GH_TOKEN = "\${{ github.token }}";
                    };
                    run = ''
                      git switch --create openpgp-policy-$(date --iso-8601)
                      git add openpgp-policy.toml
                      git commit -m 'chore: Update openpgp-policy.toml'
                      gh pr create --fill
                    '';
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.aiReview.enable {
            ai-review = {
              name = "AI Code Review";
              on.pullRequest = {
                branches = [ "**" ];
                types = [
                  "opened"
                  "reopened"
                  "synchronize"
                  "ready_for_review"
                ];
              };
              permissions = {
                contents = "read";
                pull-requests = "write";
              };
              concurrency = prConcurrency;
              jobs.review = {
                runsOn = "ubuntu-latest";
                if_ = "github.event_name == 'pull_request'";
                steps = [
                  { uses = "actions/checkout@${av.checkout}"; }
                  {
                    uses = "anthropics/claude-code-action@${av.claudeCodeAction}";
                    with_ = {
                      anthropic_api_key = "\${{ secrets.ANTHROPIC_API_KEY }}";
                      model = cfg.aiReview.model;
                    };
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.release.enable {
            release = {
              name = "GitHub Release";
              on.push = {
                tags = [ "v[0-9]+.[0-9]+.[0-9]+" ];
              };
              permissions = {
                contents = "write";
              };
              jobs.release = {
                runsOn = "ubuntu-latest";
                if_ = "startsWith(github.ref, 'refs/tags/')";
                steps = [
                  { uses = "actions/checkout@${av.checkout}"; }
                  {
                    uses = "softprops/action-gh-release@${av.ghRelease}";
                    with_ = {
                      draft = cfg.release.draft;
                      generate_release_notes = true;
                      prerelease = false;
                    };
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.reuse {
            reuse = {
              name = "REUSE compliance";
              on.pullRequest = { };
              permissions = {
                contents = "read";
              };
              concurrency = prConcurrency;
              jobs.reuse = {
                runsOn = "ubuntu-latest";
                steps = [
                  { uses = "actions/checkout@${av.checkout}"; }
                  { uses = "fsfe/reuse-action@${av.reuseAction}"; }
                ];
              };
            };
          })
        ];

        famedly.standards._internal.managedFiles =
          lib.optionals cfg.conventionalCommits [
            {
              src = config.githubActions.workflowFiles."general-checks.yml";
              dest = ".github/workflows/general-checks.yml";
            }
          ]
          ++ lib.optionals cfg.authenticateCommits [
            {
              src = config.githubActions.workflowFiles."authenticate-commits.yml";
              dest = ".github/workflows/authenticate-commits.yml";
            }
          ]
          ++ lib.optionals cfg.fastForward [
            {
              src = config.githubActions.workflowFiles."fast-forward.yml";
              dest = ".github/workflows/fast-forward.yml";
            }
          ]
          ++ lib.optionals cfg.addToProject.enable [
            {
              src = config.githubActions.workflowFiles."add-to-project.yml";
              dest = ".github/workflows/add-to-project.yml";
            }
          ]
          ++ lib.optionals cfg.updateOpenpgpPolicy.enable [
            {
              src = config.githubActions.workflowFiles."update-openpgp-policy.yml";
              dest = ".github/workflows/update-openpgp-policy.yml";
            }
          ]
          ++ lib.optionals cfg.aiReview.enable [
            {
              src = config.githubActions.workflowFiles."ai-review.yml";
              dest = ".github/workflows/ai-review.yml";
            }
          ]
          ++ lib.optionals cfg.release.enable [
            {
              src = config.githubActions.workflowFiles."release.yml";
              dest = ".github/workflows/release.yml";
            }
          ]
          ++ lib.optionals cfg.reuse [
            {
              src = config.githubActions.workflowFiles."reuse.yml";
              dest = ".github/workflows/reuse.yml";
            }
          ];
      };
    }
  );
}
