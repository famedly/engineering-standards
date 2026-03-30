{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib)
    ghExpr
    ghSecret
    ghVar
    mkRustPrepareStep
    ;
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

  config.definition = {
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
        (mkRustPrepareStep {
          shipyardToken = ghSecret "SHIPYARD_RS_TOKEN";
          registryName = ghVar "CRATE_REGISTRY_NAME";
          registryIndexUrl = ghVar "CRATE_REGISTRY_INDEX_URL";
        })
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
}
