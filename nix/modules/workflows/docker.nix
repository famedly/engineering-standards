# Docker workflow module: generates caller workflows for Docker builds.
#
# Generated files in consumer repo:
#   .github/workflows/docker-backend.yml   — Famedly Rust backend Docker pipeline
#   .github/workflows/docker.yml           — generic multi-arch Docker build & push
#   .github/workflows/github-pages.yml     — publish artifact to GitHub Pages (deploy-pages API)

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
      ref = config.famedly.standards.workflowRef;

      dockerBackendYaml = pkgs.writeText "docker-backend.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Docker backend
        on:
          push:
            branches: ["main"]
            tags: ["v*"]
          pull_request:
            branches: ["main"]

        concurrency:
          group: ''${{ github.workflow }}-''${{ github.ref }}
          cancel-in-progress: ''${{ github.ref != 'refs/heads/main' }}

        jobs:
          docker:
            uses: famedly/engineering-standards/.github/workflows/infra-docker-backend.yml@${ref}
            with:
              targets: ${cfg.dockerBackend.targets}
        ${lib.optionalString cfg.dockerBackend.oss "      oss: true"}
            secrets: inherit
      '';

      dockerYaml = pkgs.writeText "docker.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Docker
        on:
          push:
            branches: ["main"]
            tags: ["v*"]
          pull_request:
            branches: ["main"]

        concurrency:
          group: ''${{ github.workflow }}-''${{ github.ref }}
          cancel-in-progress: ''${{ github.ref != 'refs/heads/main' }}

        jobs:
          docker:
            uses: famedly/engineering-standards/.github/workflows/infra-docker.yml@${ref}
            with:
              push: ''${{ github.event_name != 'pull_request' }}
        ${lib.optionalString (cfg.docker.imageName != "") "      image_name: ${cfg.docker.imageName}"}
        ${lib.optionalString (cfg.docker.registry != "") "      registry: ${cfg.docker.registry}"}
            secrets: inherit
      '';

      dockerBakeYaml = pkgs.writeText "docker-bake.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Docker Bake
        on:
          push:
            branches: ["main"]
            tags: ["v*"]
          pull_request:
            branches: ["main"]

        concurrency:
          group: ''${{ github.workflow }}-''${{ github.ref }}
          cancel-in-progress: ''${{ github.ref != 'refs/heads/main' }}

        jobs:
          bake:
            uses: famedly/engineering-standards/.github/workflows/infra-docker-bake.yml@${ref}
            with:
              push: ''${{ github.event_name != 'pull_request' }}
        ${lib.optionalString (cfg.dockerBake.files != "") "      files: ${cfg.dockerBake.files}"}
        ${lib.optionalString (cfg.dockerBake.targets != "") "      targets: ${cfg.dockerBake.targets}"}
            secrets: inherit
      '';

      githubPagesYaml = pkgs.writeText "github-pages.yml" ''
        # managed-by: engineering-standards — do not edit manually
        # Regenerate with: nix run .#regenerateStandards
        name: Publish to GitHub Pages
        on:
          workflow_run:
            workflows: ["CI"]
            types: [completed]
            branches: [main]

        permissions:
          pages: write
          id-token: write

        jobs:
          deploy:
            if: ''${{ github.event.workflow_run.conclusion == 'success' }}
            uses: famedly/engineering-standards/.github/workflows/infra-github-pages.yml@${ref}
            with:
              artifact_name: ${cfg.githubPages.artifactName}
      '';
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
            default = "";
            description = "Docker image name (defaults to github.repository).";
          };

          registry = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Container registry (defaults to ghcr.io).";
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
            description = "Generate Docker Bake workflow for multi-target builds using docker/bake-action.";
          };

          files = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Bake definition file(s). Defaults to docker-bake.hcl.";
            example = "docker-bake.hcl";
          };

          targets = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Bake target(s) to build. Defaults to 'default'.";
            example = "my-service,my-worker";
          };
        };
      };

      config = {
        famedly.standards._internal.managedFiles =
          lib.optionals cfg.dockerBackend.enable [
            {
              src = dockerBackendYaml;
              dest = ".github/workflows/docker-backend.yml";
            }
          ]
          ++ lib.optionals cfg.docker.enable [
            {
              src = dockerYaml;
              dest = ".github/workflows/docker.yml";
            }
          ]
          ++ lib.optionals cfg.githubPages.enable [
            {
              src = githubPagesYaml;
              dest = ".github/workflows/github-pages.yml";
            }
          ]
          ++ lib.optionals cfg.dockerBake.enable [
            {
              src = dockerBakeYaml;
              dest = ".github/workflows/docker-bake.yml";
            }
          ];
      };
    }
  );
}
