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
  inherit (workflowsLib) ghExpr ghSecret ghVar;
  defaultContainer = "ghcr.io/famedly/rust-container:nightly";
in
{
  options = {
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
    };
  };

  config = {
    definition = {
      name = "Publish Rust crates";
      on.push.tags = [
        "v[0-9]+.[0-9]+.[0-9]+"
        "v[0-9]+.[0-9]+.[0-9]+-rc.[0-9]+"
      ]
      ++ config.extraTagPatterns;
      permissions.contents = "read";
      jobs.publish = {
        runsOn = "ubuntu-latest";
        if_ = "startsWith(github.ref, 'refs/tags/')";
        container = defaultContainer;
        steps = [
          { uses = "actions/checkout@${av.checkout}"; }
          {
            uses = "./.github/actions/rust-prepare";
            with_ = {
              crate_registry_name = ghVar "CRATE_REGISTRY_NAME";
              crate_registry_index_url = ghVar "CRATE_REGISTRY_INDEX_URL";
              crate_registry_ssh_privkey = ghSecret "CRATE_REGISTRY_SSH_PRIVKEY";
            };
          }
          {
            name = "Install registry token";
            run = ''
              cat << EOF > "''${CARGO_HOME}/credentials.toml"
              [${ghExpr "vars.CRATE_REGISTRY_NAME != 'crates-io' && format('registries.{0}', vars.CRATE_REGISTRY_NAME) || 'registry'"}]
              token = "${ghSecret "CRATE_REGISTRY_AUTH_TOKEN"}"
              EOF
            '';
          }
          {
            name = "Publish";
            run =
              "cargo publish ${ghExpr "vars.CRATE_REGISTRY_NAME != 'crates-io' && format('--registry {0}', vars.CRATE_REGISTRY_NAME) || ''"}"
              + lib.optionalString (config.packages != "") " --package ${config.packages}"
              + lib.optionalString (config.features != "") " --features ${config.features}";
          }
        ];
      };
    };

    extraManagedFiles =
      let
        rustCiEnabled = (famedlyConfig.github.workflows.rust-ci.enable or false);
      in
      lib.optionals (!rustCiEnabled) [
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
