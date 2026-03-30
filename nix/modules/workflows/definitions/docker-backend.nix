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
    ghEnv
    ciConcurrency
    ;
  ociURLs = famedlyConfig.github.settings.ociRegistryURLs;
in
{
  options = {
    targets = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Comma-separated list of Docker build targets.";
    };
    oss = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Publish to the public OSS container registry for releases.";
    };
  };

  config.definition = {
    name = "Docker — Rust Backend Build & Push";
    on = {
      push = {
        branches = [ "main" ];
        tags = [ "v*" ];
      };
      pullRequest.branches = [ "main" ];
    };
    permissions.contents = "read";
    concurrency = ciConcurrency;
    env = {
      OCI_REGISTRY_SNAPSHOTS = ociURLs.snapshots;
      OCI_REGISTRY_RELEASES = ociURLs.releases;
      OCI_REGISTRY_OSS = ociURLs.openSourceReleases;
    };
    jobs.docker-publish = {
      runsOn = "ubuntu-latest-16core";
      steps = [
        { uses = "actions/checkout@${av.checkout}"; }
        {
          name = "Configure private registry credentials";
          if_ = "secrets.SHIPYARD_RS_TOKEN != ''";
          env.SHIPYARD_RS_TOKEN = ghSecret "SHIPYARD_RS_TOKEN";
          run = ''
            git config --global credential.helper store
            echo "https://famedly:''${SHIPYARD_RS_TOKEN}@git.shipyard.rs" > ~/.git-credentials
            chmod 600 ~/.git-credentials
          '';
        }
        {
          name = "Build";
          shell = "bash";
          env.SHIPYARD_RS_TOKEN = ghExpr "secrets.SHIPYARD_RS_TOKEN || ''";
          run = ''
            for target in $(echo "${config.targets}" | tr ',' '\n'); do
              echo "::group::Building ''${target}"
              docker build --pull -t ''${target} --target ''${target} \
                --build-arg CARGO_REGISTRIES_FAMEDLY_INDEX="${ghVar "CRATE_REGISTRY_INDEX_URL"}" \
                --build-arg CARGO_BUILD_RUSTFLAGS="''${CARGO_BUILD_RUSTFLAGS}" \
                ''${SHIPYARD_RS_TOKEN:+--secret id=shipyard_token,env=SHIPYARD_RS_TOKEN} \
                .
              echo "::endgroup::"
            done
          '';
        }
        {
          name = "Resolve OCI registry to push";
          shell = "bash";
          run = ''
            if [ ${ghExpr "github.ref_type"} = 'branch' ]; then
              echo "OCI_REGISTRY=${ghEnv "OCI_REGISTRY_SNAPSHOTS"}" >> $GITHUB_ENV
            elif [ ${ghExpr "github.ref_type"} = 'tag' ]; then
              if [[ ${builtins.toJSON config.oss} == true ]]; then
                echo "OCI_REGISTRY=${ghEnv "OCI_REGISTRY_OSS"}" >> $GITHUB_ENV
              else
                echo "OCI_REGISTRY=${ghEnv "OCI_REGISTRY_RELEASES"}" >> $GITHUB_ENV
              fi
              if ! [[ ${ghExpr "github.ref_name"} =~ v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                echo "OCI_REGISTRY=${ghEnv "OCI_REGISTRY_SNAPSHOTS"}" >> $GITHUB_ENV
              fi
            fi
          '';
        }
        {
          name = "Tag";
          shell = "bash";
          if_ = "env.OCI_REGISTRY != null";
          env = {
            TARGETS = config.targets;
            REF_TYPE = ghExpr "github.ref_type";
            REF_NAME_RAW = ghExpr "github.head_ref || github.ref";
            TAG_NAME = ghExpr "github.ref_name";
            COMMIT_SHA = ghExpr "github.sha";
          };
          run = ''
            for target in $(echo "''${TARGETS}" | tr ',' '\n'); do
              IMAGE_PATH="${ghEnv "OCI_REGISTRY"}/''${target}"
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
            registry = ghEnv "OCI_REGISTRY";
            username = ghVar "OCI_REGISTRY_USER";
            password = ghExpr "secrets.OCI_REGISTRY_PASSWORD || secrets.GITHUB_TOKEN";
          };
        }
        {
          name = "Push";
          if_ = "env.OCI_REGISTRY != null";
          shell = "bash";
          run = ''
            for target in $(echo "${config.targets}" | tr ',' '\n'); do
              IMAGE_PATH="${ghEnv "OCI_REGISTRY"}/''${target}"
              echo "::group::Pushing ''${IMAGE_PATH}"
              docker image push --all-tags "''${IMAGE_PATH}"
              echo "::endgroup::"
            done
          '';
        }
      ];
    };
  };
}
