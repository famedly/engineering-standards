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
  notPR = ghExpr "github.event_name != 'pull_request'";
  image = "${config.registry}/${config.imageName}";
in
{
  options = {
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
    armRunner = lib.mkOption {
      type = lib.types.str;
      default = "arm-ubuntu-latest-8core";
      description = "Runner for ARM builds.";
    };
    amd64Runner = lib.mkOption {
      type = lib.types.str;
      default = "ubuntu-latest";
      description = "Runner for AMD64 builds.";
    };
  };

  config.definition = {
    name = "Docker — Multi-Arch Build & Push";
    on = {
      push = {
        branches = [ "main" ];
        tags = [ "v*" ];
      };
      pullRequest.branches = [ "main" ];
    };
    concurrency = ciConcurrency;
    jobs = {
      docker = {
        runsOn = ghExpr "matrix.runner";
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
            if_ = "github.event_name != 'pull_request'";
            uses = "docker/login-action@${av.dockerLogin}";
            with_ = {
              registry = config.registry;
              username = ghExpr "github.repository_owner";
              password = ghExpr "secrets.registry_password || secrets.GITHUB_TOKEN";
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
              context = ".";
              push = notPR;
              labels = ghExpr "steps.meta.outputs.labels";
              platforms = "linux/${ghExpr "matrix.platform"}";
              cache-from = "type=gha";
              cache-to = "type=gha,mode=max";
              sbom = true;
              outputs = "type=image,name=${image},push-by-digest=${notPR},name-canonical=true,push=${notPR}";
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
        if_ = "github.event_name != 'pull_request'";
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
              registry = config.registry;
              username = ghExpr "github.repository_owner";
              password = ghExpr "secrets.registry_password || secrets.GITHUB_TOKEN";
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
  };
}
