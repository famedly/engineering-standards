{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  repoRoot,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghSecret ciConcurrency;
  defaultContainer = "ghcr.io/famedly/rust-container:nightly";
in
{
  options = {
    runner = lib.mkOption {
      type = lib.types.str;
      default = "ubuntu-latest";
      description = "Override the runner for Rust CI jobs.";
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
    };
    packages = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Space-separated list of packages (for workspaces).";
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

  config = {
    definition = {
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
      permissions.contents = "read";
      concurrency = ciConcurrency;
      jobs = {
        lints = {
          name = "Clippy & Format";
          runsOn = config.runner;
          container = config.container;
          steps = [
            { uses = "actions/checkout@${av.checkout}"; }
            {
              uses = "./.github/actions/rust-prepare";
              with_ = {
                crate_registry_ssh_privkey = ghSecret "CRATE_REGISTRY_SSH_PRIVKEY";
                additional_packages = config.additionalPackages;
              };
            }
            {
              name = "Clippy";
              run = "cargo clippy ${config.features} --all-targets -- -D warnings";
            }
            {
              name = "Format";
              run = "cargo fmt --all -- --check";
            }
          ];
        };

        tests = {
          name = "Tests";
          runsOn = config.runner;
          container = config.container;
          steps = [
            { uses = "actions/checkout@${av.checkout}"; }
            {
              uses = "./.github/actions/rust-prepare";
              with_ = {
                crate_registry_ssh_privkey = ghSecret "CRATE_REGISTRY_SSH_PRIVKEY";
                additional_packages = config.additionalPackages;
              };
            }
            {
              name = "Tests";
              run = "cargo nextest run ${config.features}";
            }
          ];
        };
      }
      // lib.optionalAttrs config.coverage {
        coverage = {
          name = "Coverage";
          runsOn = config.runner;
          container = config.container;
          steps = [
            { uses = "actions/checkout@${av.checkout}"; }
            {
              uses = "./.github/actions/rust-prepare";
              with_ = {
                crate_registry_ssh_privkey = ghSecret "CRATE_REGISTRY_SSH_PRIVKEY";
                additional_packages = config.additionalPackages;
              };
            }
            {
              name = "Coverage";
              run = "cargo llvm-cov nextest ${config.features} --lcov --output-path lcov.info";
            }
            {
              uses = "codecov/codecov-action@${av.codecov}";
              with_ = {
                files = "lcov.info";
                token = ghSecret "CODECOV_TOKEN";
              };
            }
            {
              uses = "codecov/test-results-action@${av.testResults}";
              if_ = "!cancelled()";
              with_.token = ghSecret "CODECOV_TOKEN";
            }
          ];
        };
      }
      // lib.optionalAttrs config.typos {
        typos = {
          name = "Spell Check";
          runsOn = "ubuntu-latest";
          steps = [
            { uses = "actions/checkout@${av.checkout}"; }
            { uses = "crate-ci/typos@${av.typos}"; }
          ];
        };
      }
      // lib.optionalAttrs config.cargoDeny {
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

    extraManagedFiles = [
      {
        src = "${repoRoot}/.github/actions/rust-prepare/action.yml";
        dest = ".github/actions/rust-prepare/action.yml";
      }
      {
        src = "${repoRoot}/.github/actions/rust-prepare/prepare.sh";
        dest = ".github/actions/rust-prepare/prepare.sh";
      }
    ];
  };
}
