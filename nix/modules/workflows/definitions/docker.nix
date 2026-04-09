{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghExpr ciConcurrency;

  isSimple = config.mode == "simple";
  isWorkflowRun = config.triggerMode == "workflowRun";
  notPR = ghExpr "github.event_name != 'pull_request'";
  image = "${config.registry}/${config.imageName}";

  pushCondition =
    if config.pushOnlyOnTags then
      "startsWith(github.ref, 'refs/tags/')"
    else
      "github.event_name != 'pull_request'";

  buildArgsStr = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}=${v}") config.buildArgs);

  # ── Trigger ──────────────────────────────────────────────────────

  pushTrigger = {
    push = {
      branches = [ "main" ];
      tags = [ "v*" ];
    };
    pullRequest.branches = [ "main" ];
  };

  workflowRunTrigger = {
    workflowRun = {
      workflows = [ config.triggerWorkflow ];
      types = [ "completed" ];
    };
  };

  trigger = if isWorkflowRun then workflowRunTrigger else pushTrigger;

  workflowRunGuard = "github.event.workflow_run.conclusion == 'success'";

  # ── Simple mode: single-arch build ──────────────────────────────

  simpleJobs = {
    docker = {
      runsOn = config.amd64Runner;
      if_ = if isWorkflowRun then workflowRunGuard else null;
      permissions = {
        contents = "read";
        packages = "write";
      };
      steps = [
        { uses = "actions/checkout@${av.checkout}"; }
        {
          name = "Set up Docker Buildx";
          uses = "docker/setup-buildx-action@${av.dockerSetupBuildx}";
        }
        {
          name = "Log into registry ${config.registry}";
          if_ = pushCondition;
          uses = "docker/login-action@${av.dockerLogin}";
          with_ = {
            inherit (config) registry;
            username = config.registryUser;
            password = ghExpr "secrets.${config.registryPasswordSecret}";
          };
        }
        {
          id = "meta";
          name = "Extract Docker metadata";
          uses = "docker/metadata-action@${av.dockerMetadata}";
          with_.images = image;
        }
        {
          name = "Build and push Docker image";
          uses = "docker/build-push-action@${av.dockerBuildPush}";
          with_ = {
            inherit (config) context;
            file = config.dockerfile;
            push = pushCondition;
            tags = ghExpr "steps.meta.outputs.tags";
            labels = ghExpr "steps.meta.outputs.labels";
            cache-from = "type=gha";
            cache-to = "type=gha,mode=max";
          }
          // lib.optionalAttrs (config.buildArgs != { }) {
            build-args = buildArgsStr;
          };
        }
      ];
    };
  };

  # ── Multi-arch mode: matrix build + manifest merge ──────────────

  multiArchJobs = {
    docker = {
      runsOn = ghExpr "matrix.runner";
      if_ = if isWorkflowRun then workflowRunGuard else null;
      permissions = {
        contents = "read";
        packages = "write";
      };
      strategy = {
        failFast = false;
        matrix.include = [
          {
            platform = "amd64";
            runner = config.amd64Runner;
          }
          {
            platform = "arm64";
            runner = config.armRunner;
          }
        ];
      };
      outputs.tags = ghExpr "steps.tag.outputs.tags";
      steps = [
        { uses = "actions/checkout@${av.checkout}"; }
        {
          name = "Set up QEMU";
          uses = "docker/setup-qemu-action@${av.dockerSetupQemu}";
        }
        {
          name = "Setup Docker buildx";
          uses = "docker/setup-buildx-action@${av.dockerSetupBuildx}";
        }
        {
          name = "Log into registry ${config.registry}";
          if_ = notPR;
          uses = "docker/login-action@${av.dockerLogin}";
          with_ = {
            inherit (config) registry;
            username = config.registryUser;
            password = ghExpr "secrets.${config.registryPasswordSecret}";
          };
        }
        {
          id = "meta";
          name = "Extract Docker metadata";
          uses = "docker/metadata-action@${av.dockerMetadata}";
          with_.images = image;
        }
        {
          id = "build";
          name = "Build and push Docker image";
          uses = "docker/build-push-action@${av.dockerBuildPush}";
          with_ = {
            inherit (config) context;
            file = config.dockerfile;
            push = notPR;
            labels = ghExpr "steps.meta.outputs.labels";
            platforms = "linux/${ghExpr "matrix.platform"}";
            cache-from = "type=gha";
            cache-to = "type=gha,mode=max";
            sbom = true;
            outputs = "type=image,name=${image},push-by-digest=${notPR},name-canonical=true,push=${notPR}";
          }
          // lib.optionalAttrs (config.buildArgs != { }) {
            build-args = buildArgsStr;
          };
        }
        {
          id = "tag";
          name = "Get actual tag";
          run =
            let
              metaTags = ghExpr "toJSON(fromJSON(steps.meta.outputs.json).tags)";
            in
            "echo \"tags=$(echo '${metaTags}' | jq 'if (type) == \"array\" then .[0] else . end' | sed 's/\"//g' | cut -d ':' -f 2)\" >> $GITHUB_OUTPUT";
        }
        {
          id = "clean_registry";
          name = "Create cleaned up registry variable";
          run = ''
            echo "clean_registry=$(echo '${config.registry}' | sed 's/\//-/g')" >> $GITHUB_OUTPUT
          '';
        }
        {
          name = "Export digest";
          run = ''
            mkdir -p /tmp/digests
            digest="${ghExpr "steps.build.outputs.digest"}"
            touch "/tmp/digests/''${digest#sha256:}"
          '';
        }
        {
          name = "Upload digest";
          uses = "actions/upload-artifact@${av.uploadArtifact}";
          with_ = {
            name =
              let
                cleanReg = ghExpr "steps.clean_registry.outputs.clean_registry";
                tags = ghExpr "steps.tag.outputs.tags";
                platform = ghExpr "matrix.platform";
              in
              "digests-${cleanReg}-${config.imageName}-${tags}-${platform}";
            path = "/tmp/digests/*";
            if-no-files-found = "error";
            retention-days = 1;
          };
        }
      ];
    };

    merge = {
      runsOn = "ubuntu-latest";
      if_ = notPR;
      needs = [ "docker" ];
      steps = [
        {
          id = "clean_registry";
          name = "Create cleaned up registry variable";
          run = ''
            echo "clean_registry=$(echo '${config.registry}' | sed 's/\//-/g')" >> $GITHUB_OUTPUT
          '';
        }
        {
          name = "Download digests";
          uses = "actions/download-artifact@${av.downloadArtifact}";
          with_ = {
            path = "/tmp/digests";
            pattern =
              let
                cleanReg = ghExpr "steps.clean_registry.outputs.clean_registry";
                tags = ghExpr "needs.docker.outputs.tags";
              in
              "digests-${cleanReg}-${config.imageName}-${tags}-*";
            merge-multiple = true;
          };
        }
        {
          name = "Set up Docker Buildx";
          uses = "docker/setup-buildx-action@${av.dockerSetupBuildx}";
        }
        {
          id = "meta";
          name = "Extract Docker metadata";
          uses = "docker/metadata-action@${av.dockerMetadata}";
          with_.images = image;
        }
        {
          name = "Log into registry ${config.registry}";
          uses = "docker/login-action@${av.dockerLogin}";
          with_ = {
            inherit (config) registry;
            username = config.registryUser;
            password = ghExpr "secrets.${config.registryPasswordSecret}";
          };
        }
        {
          name = "Create manifest list and push";
          workingDirectory = "/tmp/digests";
          run = ''
            docker buildx imagetools create $(jq -cr '.tags | map("-t " + .) | join(" ")' <<< "$DOCKER_METADATA_OUTPUT_JSON") \
              $(printf '${image}@sha256:%s ' *)
          '';
        }
        {
          name = "Inspect image";
          run =
            let
              version = ghExpr "steps.meta.outputs.version";
            in
            "docker buildx imagetools inspect ${image}:${version}";
        }
        {
          name = "Inspect sbom";
          run =
            let
              version = ghExpr "steps.meta.outputs.version";
            in
            "docker buildx imagetools inspect ${image}:${version} --format '{{ json .SBOM }}' | jq";
        }
      ];
    };
  };
in
{
  options = {
    mode = lib.mkOption {
      type = lib.types.enum [
        "multi-arch"
        "simple"
      ];
      default = "multi-arch";
      description = ''
        Build mode.
        "multi-arch" builds for amd64 and arm64 using a matrix strategy
        and merges digests into a multi-platform manifest.
        "simple" does a single-platform build and push.
      '';
    };

    triggerMode = lib.mkOption {
      type = lib.types.enum [
        "push"
        "workflowRun"
      ];
      default = "push";
      description = ''
        How the workflow is triggered.
        "push" triggers on pushes to main/tags and PRs (default).
        "workflowRun" triggers after an upstream workflow completes.
      '';
    };

    triggerWorkflow = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Name of the upstream workflow (only used with workflowRun trigger mode).";
    };

    imageName = lib.mkOption {
      type = lib.types.str;
      default = ghExpr "github.repository";
      description = "Docker image name.";
    };

    registry = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io";
      description = "Container registry.";
    };

    registryUser = lib.mkOption {
      type = lib.types.str;
      default = ghExpr "github.repository_owner";
      description = "Registry login username.";
    };

    registryPasswordSecret = lib.mkOption {
      type = lib.types.str;
      default = "registry_password || secrets.GITHUB_TOKEN";
      description = "Expression for the registry password secret (without secrets. prefix if using ||).";
    };

    armRunner = lib.mkOption {
      type = lib.types.str;
      default = "arm-ubuntu-latest-8core";
      description = "Runner for ARM builds (multi-arch mode only).";
    };

    amd64Runner = lib.mkOption {
      type = lib.types.str;
      default = "ubuntu-latest";
      description = "Runner for AMD64 builds.";
    };

    context = lib.mkOption {
      type = lib.types.str;
      default = ".";
      description = "Docker build context path.";
    };

    dockerfile = lib.mkOption {
      type = lib.types.str;
      default = "Dockerfile";
      description = "Path to the Dockerfile.";
    };

    buildArgs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Docker build arguments.";
      example = {
        VERSION = "\${{ github.ref_name }}";
      };
    };

    pushOnlyOnTags = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Only push images when triggered by a tag (not on branch pushes).";
    };
  };

  config.definition = {
    name = "Docker — ${if isSimple then "Build & Push" else "Multi-Arch Build & Push"}";
    on = trigger;
    concurrency = ciConcurrency;
    jobs = if isSimple then simpleJobs else multiArchJobs;
  };
}
