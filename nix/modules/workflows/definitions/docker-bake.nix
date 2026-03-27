{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghExpr ghSecret ciConcurrency;
in
{
  options = {
    files = lib.mkOption {
      type = lib.types.str;
      default = "docker-bake.hcl";
      description = "Bake definition file(s).";
    };
    targets = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Bake target(s) to build.";
    };
  };

  config.definition = {
    name = "Docker — Bake Build & Push";
    on = {
      push = {
        branches = [ "main" ];
        tags = [ "v*" ];
      };
      pullRequest.branches = [ "main" ];
    };
    permissions = {
      contents = "read";
      packages = "write";
    };
    concurrency = ciConcurrency;
    jobs.bake = {
      runsOn = "ubuntu-latest";
      steps = [
        { uses = "actions/checkout@${av.checkout}"; }
        {
          name = "Set up Docker Buildx";
          uses = "docker/setup-buildx-action@${av.dockerSetupBuildx}";
        }
        {
          name = "Log into registry";
          if_ = "github.event_name != 'pull_request'";
          uses = "docker/login-action@${av.dockerLogin}";
          with_ = {
            registry = "ghcr.io";
            username = ghExpr "github.repository_owner";
            password = ghExpr "secrets.registry_password || secrets.GITHUB_TOKEN";
          };
        }
        {
          id = "meta";
          name = "Extract Docker metadata";
          uses = "docker/metadata-action@${av.dockerMetadata}";
          with_.images = "ghcr.io/${ghExpr "github.repository"}";
        }
        {
          name = "Build and push via Bake";
          uses = "docker/bake-action@${av.dockerBake}";
          with_ = {
            files = "${config.files}\n${ghExpr "steps.meta.outputs.bake-file"}";
            targets = config.targets;
            push = ghExpr "github.event_name != 'pull_request'";
            set = "*.cache-from=type=gha\n*.cache-to=type=gha,mode=max";
          };
        }
      ];
    };
  };
}
