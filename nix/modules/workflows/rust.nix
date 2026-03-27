# Rust workflow module: generates complete Rust CI and publishing workflows.
#
# Generated files in consumer repo:
#   .github/workflows/rust-ci.yml           — Clippy, tests, coverage, typos, cargo-deny
#   .github/workflows/publish-crate.yml     — publish to crate registry on tag push
#   .github/actions/rust-prepare/action.yml — SSH + Cargo environment setup
#   .github/actions/rust-prepare/prepare.sh — Build environment setup script

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

      rustPrepareAction = "${root}/.github/actions/rust-prepare/action.yml";
      rustPrepareScript = "${root}/.github/actions/rust-prepare/prepare.sh";

      defaultContainer = "ghcr.io/famedly/rust-container:nightly";
    in
    {
      options.famedly.standards.workflows = {
        rustCi = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate Rust CI workflow (Clippy, tests, coverage).";
          };

          runner = lib.mkOption {
            type = lib.types.str;
            default = "ubuntu-latest";
            description = "Override the runner for Rust CI jobs.";
            example = "arm-ubuntu-latest-32core";
          };

          container = lib.mkOption {
            type = lib.types.str;
            default = defaultContainer;
            description = "Override the container image for Rust CI jobs.";
          };

          features = lib.mkOption {
            type = lib.types.str;
            default = "--all-features";
            description = "Feature flags to pass to cargo commands.";
            example = "--features feat-a,feat-b";
          };

          packages = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Space-separated list of packages (for workspaces, passed as --package).";
          };

          additionalPackages = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Additional OS-level packages to install during preparation.";
          };

          coverage = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable coverage job with llvm-cov + Codecov upload.";
          };

          typos = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable spell-check job with crate-ci/typos.";
          };

          cargoDeny = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable license/dependency audit job with cargo-deny.";
          };
        };

        rustPublish = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate crate publish workflow triggered on version tags.";
          };

          packages = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Space-separated list of packages to publish (for workspaces).";
          };

          features = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Features to pass to cargo publish.";
          };

          extraTagPatterns = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional tag patterns to trigger publishing.";
            example = [ "[a-zA-Z-_]+v[0-9]+.[0-9]+.[0-9]+" ];
          };
        };
      };

      config = {
        githubActions.workflows = lib.mkMerge [
          (lib.mkIf cfg.rustCi.enable {
            rust-ci = {
              name = "Rust CI";
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
              jobs = {
                lints = {
                  name = "Clippy & Format";
                  runsOn = cfg.rustCi.runner;
                  container = cfg.rustCi.container;
                  steps = [
                    { uses = "actions/checkout@${av.checkout}"; }
                    {
                      uses = "./.github/actions/rust-prepare";
                      with_ = {
                        crate_registry_ssh_privkey = "\${{ secrets.CRATE_REGISTRY_SSH_PRIVKEY }}";
                        additional_packages = cfg.rustCi.additionalPackages;
                      };
                    }
                    {
                      name = "Clippy";
                      run = "cargo clippy ${cfg.rustCi.features} --all-targets -- -D warnings";
                    }
                    {
                      name = "Format";
                      run = "cargo fmt --all -- --check";
                    }
                  ];
                };

                tests = {
                  name = "Tests";
                  runsOn = cfg.rustCi.runner;
                  container = cfg.rustCi.container;
                  steps = [
                    { uses = "actions/checkout@${av.checkout}"; }
                    {
                      uses = "./.github/actions/rust-prepare";
                      with_ = {
                        crate_registry_ssh_privkey = "\${{ secrets.CRATE_REGISTRY_SSH_PRIVKEY }}";
                        additional_packages = cfg.rustCi.additionalPackages;
                      };
                    }
                    {
                      name = "Tests";
                      run = "cargo nextest run ${cfg.rustCi.features}";
                    }
                  ];
                };
              }
              // lib.optionalAttrs cfg.rustCi.coverage {
                coverage = {
                  name = "Coverage";
                  runsOn = cfg.rustCi.runner;
                  container = cfg.rustCi.container;
                  steps = [
                    { uses = "actions/checkout@${av.checkout}"; }
                    {
                      uses = "./.github/actions/rust-prepare";
                      with_ = {
                        crate_registry_ssh_privkey = "\${{ secrets.CRATE_REGISTRY_SSH_PRIVKEY }}";
                        additional_packages = cfg.rustCi.additionalPackages;
                      };
                    }
                    {
                      name = "Coverage";
                      run = "cargo llvm-cov nextest ${cfg.rustCi.features} --lcov --output-path lcov.info";
                    }
                    {
                      uses = "codecov/codecov-action@${av.codecov}";
                      with_ = {
                        files = "lcov.info";
                        token = "\${{ secrets.CODECOV_TOKEN }}";
                      };
                    }
                    {
                      uses = "codecov/test-results-action@${av.testResults}";
                      if_ = "!cancelled()";
                      with_ = {
                        token = "\${{ secrets.CODECOV_TOKEN }}";
                      };
                    }
                  ];
                };
              }
              // lib.optionalAttrs cfg.rustCi.typos {
                typos = {
                  name = "Spell Check";
                  runsOn = "ubuntu-latest";
                  steps = [
                    { uses = "actions/checkout@${av.checkout}"; }
                    { uses = "crate-ci/typos@${av.typos}"; }
                  ];
                };
              }
              // lib.optionalAttrs cfg.rustCi.cargoDeny {
                deny = {
                  name = "Cargo Deny";
                  runsOn = "ubuntu-latest";
                  steps = [
                    { uses = "actions/checkout@${av.checkout}"; }
                    { uses = "embarkstudios/cargo-deny-action@${av.cargoDeny}"; }
                  ];
                };
              };
            };
          })

          (lib.mkIf cfg.rustPublish.enable {
            publish-crate = {
              name = "Publish Rust crates";
              on.push.tags = [
                "v[0-9]+.[0-9]+.[0-9]+"
                "v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+"
              ]
              ++ cfg.rustPublish.extraTagPatterns;
              permissions = {
                contents = "read";
              };
              jobs.publish = {
                runsOn = "ubuntu-latest";
                if_ = "startsWith(github.ref, 'refs/tags/')";
                container = defaultContainer;
                steps = [
                  { uses = "actions/checkout@${av.checkout}"; }
                  {
                    uses = "./.github/actions/rust-prepare";
                    with_ = {
                      crate_registry_name = "\${{ vars.CRATE_REGISTRY_NAME }}";
                      crate_registry_index_url = "\${{ vars.CRATE_REGISTRY_INDEX_URL }}";
                      crate_registry_ssh_privkey = "\${{ secrets.CRATE_REGISTRY_SSH_PRIVKEY }}";
                    };
                  }
                  {
                    name = "Install registry token";
                    run = ''
                      cat << EOF > "''${CARGO_HOME}/credentials.toml"
                      [''${{ vars.CRATE_REGISTRY_NAME != 'crates-io' && format('registries.{0}', vars.CRATE_REGISTRY_NAME) || 'registry' }}]
                      token = "''${{ secrets.CRATE_REGISTRY_AUTH_TOKEN }}"
                      EOF
                    '';
                  }
                  {
                    name = "Publish";
                    run =
                      "cargo publish \${{ vars.CRATE_REGISTRY_NAME != 'crates-io' && format('--registry {0}', vars.CRATE_REGISTRY_NAME) || '' }}"
                      + lib.optionalString (cfg.rustPublish.packages != "") " --package ${cfg.rustPublish.packages}"
                      + lib.optionalString (cfg.rustPublish.features != "") " --features ${cfg.rustPublish.features}";
                  }
                ];
              };
            };
          })
        ];

        famedly.standards._internal.managedFiles =
          lib.optionals cfg.rustCi.enable [
            {
              src = config.githubActions.workflowFiles."rust-ci.yml";
              dest = ".github/workflows/rust-ci.yml";
            }
            {
              src = rustPrepareAction;
              dest = ".github/actions/rust-prepare/action.yml";
            }
            {
              src = rustPrepareScript;
              dest = ".github/actions/rust-prepare/prepare.sh";
            }
          ]
          ++ lib.optionals cfg.rustPublish.enable [
            {
              src = config.githubActions.workflowFiles."publish-crate.yml";
              dest = ".github/workflows/publish-crate.yml";
            }
          ]
          ++ lib.optionals (cfg.rustPublish.enable && !cfg.rustCi.enable) [
            {
              src = rustPrepareAction;
              dest = ".github/actions/rust-prepare/action.yml";
            }
            {
              src = rustPrepareScript;
              dest = ".github/actions/rust-prepare/prepare.sh";
            }
          ];
      };
    }
  );
}
