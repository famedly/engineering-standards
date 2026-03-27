# Docker workflow module: generates complete Docker build & push workflows.
#
# Generated files in consumer repo:
#   .github/workflows/docker-backend.yml   — Famedly Rust backend Docker pipeline
#   .github/workflows/docker.yml           — generic multi-arch Docker build & push
#   .github/workflows/docker-bake.yml      — Docker Bake multi-target builds
#   .github/workflows/github-pages.yml     — publish artifact to GitHub Pages

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

      dockerConcurrency = {
        group = "\${{ github.workflow }}-\${{ github.ref }}";
        cancelInProgress = true;
      };
    in
    {
      options.famedly.standards.workflows = {
        dockerBackend = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate Famedly Rust backend Docker workflow.";
          };

          targets = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Comma-separated list of Docker build targets.";
            example = "my-service,my-worker";
          };

          oss = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Publish to the public OSS container registry for releases.";
          };
        };

        docker = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate generic multi-arch Docker build workflow.";
          };

          imageName = lib.mkOption {
            type = lib.types.str;
            default = "\${{ github.repository }}";
            description = "Docker image name (defaults to github.repository).";
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

        githubPages = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate GitHub Pages publish workflow (deploy-pages API).";
          };

          artifactName = lib.mkOption {
            type = lib.types.str;
            default = "github-pages";
            description = "Name of the build artifact to publish.";
          };
        };

        dockerBake = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Generate Docker Bake workflow for multi-target builds.";
          };

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
      };

      config = {
        githubActions.workflows = lib.mkMerge [
          (lib.mkIf cfg.dockerBackend.enable {
            docker-backend = {
              name = "Docker — Rust Backend Build & Push";
              on = {
                push = {
                  branches = [ "main" ];
                  tags = [ "v*" ];
                };
                pullRequest.branches = [ "main" ];
              };
              permissions = {
                contents = "read";
              };
              concurrency = dockerConcurrency;
              env = {
                OCI_REGISTRY_SNAPSHOTS = "registry.famedly.net/docker-nightly";
                OCI_REGISTRY_RELEASES = "registry.famedly.net/docker-releases";
                OCI_REGISTRY_OSS = "registry.famedly.net/docker-oss";
              };
              jobs.docker-publish = {
                runsOn = "ubuntu-latest-16core";
                steps = [
                  { uses = "actions/checkout@${av.checkout}"; }
                  {
                    name = "Setup SSH Keys and known_hosts";
                    env = {
                      SSH_AUTH_SOCK = "/tmp/ssh_agent.sock";
                    };
                    run = ''
                      mkdir -p ~/.ssh
                      ssh-keyscan git.shipyard.rs >> ~/.ssh/known_hosts
                      ssh-agent -a $SSH_AUTH_SOCK > /dev/null
                      ssh-add - <<< "''${{ secrets.CRATE_REGISTRY_SSH_PRIVKEY }}" || true
                    '';
                  }
                  {
                    name = "Build";
                    shell = "bash";
                    env = {
                      SSH_AUTH_SOCK = "/tmp/ssh_agent.sock";
                    };
                    run = ''
                      for target in $(echo "${cfg.dockerBackend.targets}" | tr ',' '\n'); do
                        echo "::group::Building ''${target}"
                        docker build --pull -t ''${target} --target ''${target} \
                          --build-arg CARGO_REGISTRIES_FAMEDLY_INDEX="''${{ vars.CRATE_REGISTRY_INDEX_URL }}" \
                          --build-arg CARGO_BUILD_RUSTFLAGS="''${CARGO_BUILD_RUSTFLAGS}" \
                          --ssh default .
                        echo "::endgroup::"
                      done
                    '';
                  }
                  {
                    name = "Resolve OCI registry to push";
                    shell = "bash";
                    run = ''
                      if [ ''${{ github.ref_type }} = 'branch' ]; then
                        echo "OCI_REGISTRY=''${{ env.OCI_REGISTRY_SNAPSHOTS }}" >> $GITHUB_ENV
                      elif [ ''${{ github.ref_type }} = 'tag' ]; then
                        if [[ ${builtins.toJSON cfg.dockerBackend.oss} == true ]]; then
                          echo "OCI_REGISTRY=''${{ env.OCI_REGISTRY_OSS }}" >> $GITHUB_ENV
                        else
                          echo "OCI_REGISTRY=''${{ env.OCI_REGISTRY_RELEASES }}" >> $GITHUB_ENV
                        fi
                        if ! [[ ''${{ github.ref_name }} =~ v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                          echo "OCI_REGISTRY=''${{ env.OCI_REGISTRY_SNAPSHOTS }}" >> $GITHUB_ENV
                        fi
                      fi
                    '';
                  }
                  {
                    name = "Tag";
                    shell = "bash";
                    if_ = "env.OCI_REGISTRY != null";
                    env = {
                      TARGETS = cfg.dockerBackend.targets;
                      REF_TYPE = "\${{ github.ref_type }}";
                      REF_NAME_RAW = "\${{ github.head_ref || github.ref }}";
                      TAG_NAME = "\${{ github.ref_name }}";
                      COMMIT_SHA = "\${{ github.sha }}";
                    };
                    run = ''
                      for target in $(echo "''${TARGETS}" | tr ',' '\n'); do
                        IMAGE_PATH="''${{ env.OCI_REGISTRY }}/''${target}"
                        echo "::group::Tagging ''${IMAGE_PATH}"
                        if [ "''${REF_TYPE}" = 'branch' ]; then
                          REF_NAME=$(echo "''${REF_NAME_RAW}" | sed -r "s|^refs/heads/(.*)$|\1|" | sed -r "s|/|-|g")
                          docker tag "''${target}" "''${IMAGE_PATH}:''${REF_NAME}"
                        elif [ "''${REF_TYPE}" = 'tag' ]; then
                          if [[ "''${TAG_NAME}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                            docker tag "''${target}" "''${IMAGE_PATH}:latest"
                          fi
                          docker tag "''${target}" "''${IMAGE_PATH}:''${TAG_NAME}"
                        fi
                        docker tag "''${target}" "''${IMAGE_PATH}:''${COMMIT_SHA}"
                        echo "::endgroup::"
                      done
                    '';
                  }
                  {
                    name = "Log into registry";
                    uses = "famedly/login-action@${av.famedlyLogin}";
                    if_ = "env.OCI_REGISTRY != null";
                    with_ = {
                      registry = "\${{ env.OCI_REGISTRY }}";
                      username = "\${{ vars.OCI_REGISTRY_USER }}";
                      password = "\${{ secrets.OCI_REGISTRY_PASSWORD || secrets.GITHUB_TOKEN }}";
                    };
                  }
                  {
                    name = "Push";
                    if_ = "env.OCI_REGISTRY != null";
                    shell = "bash";
                    run = ''
                      for target in $(echo "${cfg.dockerBackend.targets}" | tr ',' '\n'); do
                        IMAGE_PATH="''${{ env.OCI_REGISTRY }}/''${target}"
                        echo "::group::Pushing ''${IMAGE_PATH}"
                        docker image push --all-tags "''${IMAGE_PATH}"
                        echo "::endgroup::"
                      done
                    '';
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.docker.enable {
            docker = {
              name = "Docker — Multi-Arch Build & Push";
              on = {
                push = {
                  branches = [ "main" ];
                  tags = [ "v*" ];
                };
                pullRequest.branches = [ "main" ];
              };
              concurrency = dockerConcurrency;
              jobs = {
                docker = {
                  runsOn = "\${{ matrix.runner }}";
                  permissions = {
                    contents = "read";
                    packages = "write";
                  };
                  strategy = {
                    failFast = false;
                    matrix = {
                      include = [
                        {
                          platform = "amd64";
                          runner = cfg.docker.amd64Runner;
                        }
                        {
                          platform = "arm64";
                          runner = cfg.docker.armRunner;
                        }
                      ];
                    };
                  };
                  outputs = {
                    tags = "\${{ steps.tag.outputs.tags }}";
                  };
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
                      name = "Log into registry ${cfg.docker.registry}";
                      if_ = "github.event_name != 'pull_request'";
                      uses = "docker/login-action@${av.dockerLogin}";
                      with_ = {
                        registry = cfg.docker.registry;
                        username = "\${{ github.repository_owner }}";
                        password = "\${{ secrets.registry_password || secrets.GITHUB_TOKEN }}";
                      };
                    }
                    {
                      id = "meta";
                      name = "Extract Docker metadata";
                      uses = "docker/metadata-action@${av.dockerMetadata}";
                      with_ = {
                        images = "${cfg.docker.registry}/${cfg.docker.imageName}";
                      };
                    }
                    {
                      id = "build";
                      name = "Build and push Docker image";
                      uses = "docker/build-push-action@${av.dockerBuildPush}";
                      with_ = {
                        context = ".";
                        push = "\${{ github.event_name != 'pull_request' }}";
                        labels = "\${{ steps.meta.outputs.labels }}";
                        platforms = "linux/\${{ matrix.platform }}";
                        cache-from = "type=gha";
                        cache-to = "type=gha,mode=max";
                        sbom = true;
                        outputs = "type=image,name=${cfg.docker.registry}/${cfg.docker.imageName},push-by-digest=\${{ github.event_name != 'pull_request' }},name-canonical=true,push=\${{ github.event_name != 'pull_request' }}";
                      };
                    }
                    {
                      id = "tag";
                      name = "Get actual tag";
                      run = "echo \"tags=$(echo '\${{ toJSON(fromJSON(steps.meta.outputs.json).tags) }}' | jq 'if (type) == \"array\" then .[0] else . end' | sed 's/\"//g' | cut -d ':' -f 2)\" >> $GITHUB_OUTPUT";
                    }
                    {
                      id = "clean_registry";
                      name = "Create cleaned up registry variable";
                      run = ''
                        echo "clean_registry=$(echo '${cfg.docker.registry}' | sed 's/\//-/g')" >> $GITHUB_OUTPUT
                      '';
                    }
                    {
                      name = "Export digest";
                      run = ''
                        mkdir -p /tmp/digests
                        digest="''${{ steps.build.outputs.digest }}"
                        touch "/tmp/digests/''${digest#sha256:}"
                      '';
                    }
                    {
                      name = "Upload digest";
                      uses = "actions/upload-artifact@${av.uploadArtifact}";
                      with_ = {
                        name = "digests-\${{ steps.clean_registry.outputs.clean_registry }}-${cfg.docker.imageName}-\${{ steps.tag.outputs.tags }}-\${{ matrix.platform }}";
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
                        echo "clean_registry=$(echo '${cfg.docker.registry}' | sed 's/\//-/g')" >> $GITHUB_OUTPUT
                      '';
                    }
                    {
                      name = "Download digests";
                      uses = "actions/download-artifact@${av.downloadArtifact}";
                      with_ = {
                        path = "/tmp/digests";
                        pattern = "digests-\${{ steps.clean_registry.outputs.clean_registry }}-${cfg.docker.imageName}-\${{ needs.docker.outputs.tags }}-*";
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
                      with_ = {
                        images = "${cfg.docker.registry}/${cfg.docker.imageName}";
                      };
                    }
                    {
                      name = "Log into registry ${cfg.docker.registry}";
                      uses = "docker/login-action@${av.dockerLogin}";
                      with_ = {
                        registry = cfg.docker.registry;
                        username = "\${{ github.repository_owner }}";
                        password = "\${{ secrets.registry_password || secrets.GITHUB_TOKEN }}";
                      };
                    }
                    {
                      name = "Create manifest list and push";
                      workingDirectory = "/tmp/digests";
                      run = ''
                        docker buildx imagetools create $(jq -cr '.tags | map("-t " + .) | join(" ")' <<< "$DOCKER_METADATA_OUTPUT_JSON") \
                          $(printf '${cfg.docker.registry}/${cfg.docker.imageName}@sha256:%s ' *)
                      '';
                    }
                    {
                      name = "Inspect image";
                      run = "docker buildx imagetools inspect ${cfg.docker.registry}/${cfg.docker.imageName}:\${{ steps.meta.outputs.version }}";
                    }
                    {
                      name = "Inspect sbom";
                      run = "docker buildx imagetools inspect ${cfg.docker.registry}/${cfg.docker.imageName}:\${{ steps.meta.outputs.version }} --format '{{ json .SBOM }}' | jq";
                    }
                  ];
                };
              };
            };
          })

          (lib.mkIf cfg.dockerBake.enable {
            docker-bake = {
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
              concurrency = dockerConcurrency;
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
                      username = "\${{ github.repository_owner }}";
                      password = "\${{ secrets.registry_password || secrets.GITHUB_TOKEN }}";
                    };
                  }
                  {
                    id = "meta";
                    name = "Extract Docker metadata";
                    uses = "docker/metadata-action@${av.dockerMetadata}";
                    with_ = {
                      images = "ghcr.io/\${{ github.repository }}";
                    };
                  }
                  {
                    name = "Build and push via Bake";
                    uses = "docker/bake-action@${av.dockerBake}";
                    with_ = {
                      files = "${cfg.dockerBake.files}\n\${{ steps.meta.outputs.bake-file }}";
                      targets = cfg.dockerBake.targets;
                      push = "\${{ github.event_name != 'pull_request' }}";
                      set = "*.cache-from=type=gha\n*.cache-to=type=gha,mode=max";
                    };
                  }
                ];
              };
            };
          })

          (lib.mkIf cfg.githubPages.enable {
            github-pages = {
              name = "Publish to GitHub Pages";
              on.workflowRun = {
                workflows = [ "CI" ];
                types = [ "completed" ];
                branches = [ "main" ];
              };
              permissions = {
                pages = "write";
                id-token = "write";
              };
              jobs.deploy = {
                runsOn = "ubuntu-latest";
                if_ = "github.event.workflow_run.conclusion == 'success'";
                environment = {
                  name = "github-pages";
                  url = "\${{ steps.deploy.outputs.page_url }}";
                };
                steps = [
                  {
                    uses = "actions/download-artifact@${av.downloadArtifact}";
                    with_ = {
                      name = cfg.githubPages.artifactName;
                      path = "dist";
                    };
                  }
                  { uses = "actions/configure-pages@${av.configurePages}"; }
                  {
                    uses = "actions/upload-pages-artifact@${av.uploadPagesArtifact}";
                    with_ = {
                      path = "dist";
                    };
                  }
                  {
                    id = "deploy";
                    uses = "actions/deploy-pages@${av.deployPages}";
                  }
                ];
              };
            };
          })
        ];

        famedly.standards._internal.managedFiles =
          lib.optionals cfg.dockerBackend.enable [
            {
              src = config.githubActions.workflowFiles."docker-backend.yml";
              dest = ".github/workflows/docker-backend.yml";
            }
          ]
          ++ lib.optionals cfg.docker.enable [
            {
              src = config.githubActions.workflowFiles."docker.yml";
              dest = ".github/workflows/docker.yml";
            }
          ]
          ++ lib.optionals cfg.dockerBake.enable [
            {
              src = config.githubActions.workflowFiles."docker-bake.yml";
              dest = ".github/workflows/docker-bake.yml";
            }
          ]
          ++ lib.optionals cfg.githubPages.enable [
            {
              src = config.githubActions.workflowFiles."github-pages.yml";
              dest = ".github/workflows/github-pages.yml";
            }
          ];
      };
    }
  );
}
