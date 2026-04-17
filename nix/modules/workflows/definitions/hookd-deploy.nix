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
  inherit (workflowsLib) ghSecret;
in
{
  options = {
    triggerWorkflow = lib.mkOption {
      type = lib.types.str;
      default = "Docker — Multi-Arch Build & Push";
      description = "Name of the upstream workflow whose successful completion triggers deployment.";
    };

    hookdUrl = lib.mkOption {
      type = lib.types.str;
      description = "Base URL of the Hookd server.";
      example = "https://my-service-webhook.famedly.de";
    };

    hookdEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "/hookd/hook/deploy";
      description = "Deploy endpoint path on the Hookd server.";
    };

    secretName = lib.mkOption {
      type = lib.types.str;
      default = "HOOKD_BASIC_AUTH_PASSWORD";
      description = "GitHub secret containing the Hookd basic-auth password.";
    };

    environment = lib.mkOption {
      type = lib.types.str;
      default = "production";
      description = "GitHub deployment environment name.";
    };

    tagPrefix = lib.mkOption {
      type = lib.types.str;
      default = "v";
      description = "Only deploy when the triggering run's head_branch starts with this prefix.";
    };
  };

  config = {
    extraManagedFiles = [
      {
        src = repoRoot + "/nix/modules/workflows/files/hookd.py";
        dest = ".github/workflows/hookd.py";
      }
    ];

    definition = {
      name = "Hookd Deploy";
      on.workflowRun = {
        workflows = [ config.triggerWorkflow ];
        types = [ "completed" ];
      };
      permissions.contents = "read";
      jobs.deploy = {
        name = "Deploy via Hookd";
        runsOn = "ubuntu-latest";
        if_ = "github.event.workflow_run.conclusion == 'success' && startsWith(github.event.workflow_run.head_branch, '${config.tagPrefix}')";
        environment.name = config.environment;
        steps = [
          { uses = av."actions/checkout"; }
          {
            name = "Deploy";
            env = {
              HOOKD_URL = config.hookdUrl;
              HOOKD_ENDPOINT = config.hookdEndpoint;
              BASIC_AUTH_PASS = ghSecret config.secretName;
            };
            run = "pip install --quiet requests && python .github/workflows/hookd.py";
          }
        ];
      };
    };
  };
}
