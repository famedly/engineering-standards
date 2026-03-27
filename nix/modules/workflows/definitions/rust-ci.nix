{
  config,
  lib,
  inputs,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib)
    ghSecret
    ciConcurrency
    nixSetupStep
    mkNixInstallStep
    mkRustPrepareStep
    ;
  nixpkgsRev = inputs.nixpkgs.rev;
in
{
  options = {
    runner = lib.mkOption {
      type = lib.types.str;
      default = "ubuntu-latest";
      description = "Runner label for Rust CI jobs.";
    };
    container = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Docker container image to run jobs in.
        When null (default), jobs run on the runner with dtolnay/rust-toolchain
        installing the Rust toolchain. Set to a container image to use a
        pre-built container instead (which must include cargo, nextest, etc.).
      '';
    };
    rustToolchain = lib.mkOption {
      type = lib.types.str;
      default = "stable";
      description = ''
        Rust toolchain channel for dtolnay/rust-toolchain (used when container = null).
        Examples: "stable", "nightly", "1.85.0".
      '';
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
      description = "Enable spell-check job with typos.";
    };
    cargoDeny = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable license/dependency audit job with cargo-deny.";
    };
  };

  config.definition =
    let
      containerAttr = lib.optionalAttrs (config.container != null) { container = config.container; };

      # When using a container, the container already has the Rust toolchain.
      # When running without a container, install Rust via dtolnay/rust-toolchain
      # and cargo-nextest via nix.
      jobSetupSteps =
        if config.container != null then
          [
            { uses = "actions/checkout@${av.checkout}"; }
            (mkRustPrepareStep {
              sshPrivkey = ghSecret "CRATE_REGISTRY_SSH_PRIVKEY";
              additionalPackages = config.additionalPackages;
            })
          ]
        else
          [
            { uses = "actions/checkout@${av.checkout}"; }
            {
              uses = "dtolnay/rust-toolchain@${av.rustToolchain}";
              with_ = {
                toolchain = config.rustToolchain;
                components = "clippy,rustfmt";
              };
            }
            (nixSetupStep av.installNix)
            (mkNixInstallStep nixpkgsRev "cargo-nextest")
            (mkRustPrepareStep {
              sshPrivkey = ghSecret "CRATE_REGISTRY_SSH_PRIVKEY";
              additionalPackages = config.additionalPackages;
            })
          ];
    in
    {
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
        tests = {
          name = "Tests";
          runsOn = config.runner;
          steps = jobSetupSteps ++ [
            {
              name = "Tests";
              run = "cargo nextest run ${config.features}";
            }
          ];
        }
        // containerAttr;
      }
      // lib.optionalAttrs config.coverage {
        coverage = {
          name = "Coverage";
          runsOn = config.runner;
          steps = jobSetupSteps ++ [
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
        }
        // containerAttr;
      }
      // lib.optionalAttrs config.typos {
        typos = {
          name = "Spell Check";
          runsOn = "ubuntu-latest";
          steps = [
            { uses = "actions/checkout@${av.checkout}"; }
            (nixSetupStep av.installNix)
            (mkNixInstallStep nixpkgsRev "typos")
            {
              name = "Run typos";
              run = "typos";
            }
          ];
        };
      }
      // lib.optionalAttrs config.cargoDeny {
        deny = {
          name = "Cargo Deny";
          runsOn = "ubuntu-latest";
          steps = [
            { uses = "actions/checkout@${av.checkout}"; }
            (nixSetupStep av.installNix)
            (mkNixInstallStep nixpkgsRev "cargo-deny")
            {
              name = "Run cargo deny";
              run = "cargo deny check";
            }
          ];
        };
      };
    };
}
