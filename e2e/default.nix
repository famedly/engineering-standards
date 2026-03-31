# e2e testing module: reproducible k3d + Argo CD environment.
#
# Enables a complete local/CI e2e environment with:
#   - k3d cluster + local OCI registry
#   - Argo CD Core (Application Controller only, ~2 pods)
#   - Helm chart packaged at Nix build time (deterministic)
#   - OpenObserve for logs/metrics/traces (kubectl apply, not Argo)
#   - Seed script for API setup and .env.e2e generation
#   - famedly-e2e-up / famedly-e2e-down / famedly-e2e apps
#
# Usage in consumer flake.nix:
#
#   famedly.standards.e2e = {
#     enable = true;
#     chart = {
#       repo = "https://github.com/famedly/helm-charts.git";
#       path = "e2e-platform";
#       rev  = "e2e-platform-0.1.0";
#       hash = "sha256-XXXX...";
#     };
#     portForwards = [ "8080:8080@loadbalancer" "8008:8008@loadbalancer" ];
#     seed = {
#       script = ./e2e/seed.sh;
#       runtimeInputs = with pkgs; [ curl jq ];
#     };
#     testCommand = "cargo nextest run -E 'test(e2e)'";
#   };

{ flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.famedly.standards.e2e;

      helmLib = pkgs.callPackage ./helm.nix { };
      argoLib = pkgs.callPackage ./argocd.nix { };

      # External URL used by helm push (host → registry container).
      registryUrl = "${cfg.registry.name}:${toString cfg.registry.port}";

      # In-cluster URL for Argo CD Applications.
      # The .localhost TLD resolves to 127.0.0.1 inside pods, so we create
      # a K8s Service+Endpoints in the argocd namespace pointing to the
      # registry container's docker-network IP.  The script sets this up;
      # we just need a deterministic name here.
      inClusterRegistryUrl = "e2e-registry.argocd.svc.cluster.local:5000";

      # Resolve and package the chart at Nix build time.
      # Only evaluated when cfg.enable = true (inside lib.mkIf block).
      chartSrc = helmLib.resolveChartSource cfg.chart;
      chartPkg = helmLib.packageChart {
        inherit chartSrc;
        name = "e2e-platform";
      };

      # Extract the chart version from Chart.yaml at eval time (no IFD).
      # Reads the Chart.yaml from the resolved source path.
      chartVersion =
        let
          chartYaml = builtins.readFile "${chartSrc}/Chart.yaml";
          # Match "version: X.Y.Z" anywhere in the file.
          m = builtins.match ".*\nversion:[ \t]+([0-9][^\n]*).*" chartYaml;
        in
        if m != null then lib.head m else "0.0.0";

      # Build Argo Application CR JSON for the e2e-platform chart.
      platformAppJson = argoLib.makeApplication {
        name = "e2e-platform";
        registryUrl = inClusterRegistryUrl;
        inherit chartVersion;
        namespace = cfg.namespace;
        values = cfg.values;
      };

      # Build the directory of all Application CR YAML files.
      argoAppsDir = argoLib.makeApplicationsDir {
        "e2e-platform" = platformAppJson;
      };

      # Seed script wrapped with its runtime dependencies.
      seedScriptWrapped =
        if cfg.seed.script != null then
          pkgs.writeShellApplication {
            name = "e2e-seed-inner";
            runtimeInputs = cfg.seed.runtimeInputs;
            text = builtins.readFile cfg.seed.script;
          }
        else
          null;

      # Image pull secrets setup snippet (shell, injected into e2e-up env).
      imagePullSecretsScript = lib.concatMapStringsSep "\n" (
        s: ''
          kubectl create secret docker-registry ${lib.escapeShellArg s.name} \
            --docker-server=${lib.escapeShellArg s.registry} \
            --docker-username=${lib.escapeShellArg s.username} \
            --docker-password="''${${s.password}:-}" \
            --dry-run=client -o yaml | kubectl apply -f - || true
        ''
      ) cfg.imagePullSecrets;

      # Common shell variables injected into every e2e app.
      # Using export so shellcheck (SC2034) does not flag them as unused
      # in scripts that only use a subset of these variables.
      commonEnv = ''
        export CLUSTER_NAME=${lib.escapeShellArg cfg.clusterName}
        export REGISTRY_NAME=${lib.escapeShellArg cfg.registry.name}
        export REGISTRY_PORT=${toString cfg.registry.port}
        export ENV_FILE=${lib.escapeShellArg cfg.seed.envFile}
        export OBS_PORT=${toString cfg.observability.port}
        export OTEL_PORT=${toString cfg.observability.otelPort}
        export READY_SELECTOR=${lib.escapeShellArg cfg.readySelector}
        export READY_TIMEOUT=${lib.escapeShellArg cfg.readyTimeout}
      '';

      # famedly-e2e-up
      e2eUp = pkgs.writeShellApplication {
        name = "famedly-e2e-up";
        runtimeInputs = with pkgs; [
          k3d
          kubectl
          kubernetes-helm
          coreutils
          bash
        ];
        text =
          commonEnv
          + ''
            declare -a CHART_PACKAGES=(${lib.escapeShellArg (toString chartPkg)})
            export CHART_NAMESPACE=${lib.escapeShellArg cfg.namespace}
            ARGO_INSTALL=${lib.escapeShellArg (toString argoLib.installManifest)}
            OPENOBSERVE_MANIFEST=${
              if cfg.observability.enable then
                lib.escapeShellArg (toString ./manifests/openobserve.yaml)
              else
                "\"\""
            }
            # PostgreSQL manifest: pre-deployed before the main chart so that
            # Zitadel's pre-install hook can connect to the DB.
            POSTGRESQL_MANIFEST=${lib.escapeShellArg (toString ./manifests/postgresql.yaml)}
            declare -a EXTRA_MANIFESTS=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.extraManifests})
            SEED_SCRIPT=${
              lib.escapeShellArg (if seedScriptWrapped != null then lib.getExe seedScriptWrapped else "")
            }
            declare -a PORT_FORWARDS=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.portForwards})

            ${imagePullSecretsScript}

          ''
          + builtins.readFile ./scripts/e2e-up.sh;
      };

      # famedly-e2e-down
      e2eDown = pkgs.writeShellApplication {
        name = "famedly-e2e-down";
        runtimeInputs = with pkgs; [
          k3d
          coreutils
        ];
        text = commonEnv + builtins.readFile ./scripts/e2e-down.sh;
      };

      # famedly-e2e (CI: up → test → down)
      e2eRun = pkgs.writeShellApplication {
        name = "famedly-e2e";
        runtimeInputs = with pkgs; [
          k3d
          kubectl
          kubernetes-helm
          coreutils
          bash
          e2eUp
          e2eDown
        ];
        text =
          commonEnv
          + ''
            TEST_COMMAND=${lib.escapeShellArg cfg.testCommand}
          ''
          + builtins.readFile ./scripts/e2e-run.sh;
      };

      # famedly-e2e-seed
      e2eSeed = pkgs.writeShellApplication {
        name = "famedly-e2e-seed";
        runtimeInputs =
          with pkgs;
          [
            k3d
            kubectl
            bash
          ]
          ++ cfg.seed.runtimeInputs;
        text =
          commonEnv
          + ''
            SEED_SCRIPT=${
              lib.escapeShellArg (if seedScriptWrapped != null then lib.getExe seedScriptWrapped else "")
            }
          ''
          + builtins.readFile ./scripts/e2e-seed.sh;
      };

      # famedly-e2e-status
      e2eStatus = pkgs.writeShellApplication {
        name = "famedly-e2e-status";
        runtimeInputs = with pkgs; [
          k3d
          kubectl
          coreutils
        ];
        text = commonEnv + builtins.readFile ./scripts/e2e-status.sh;
      };

      # famedly-e2e-logs
      e2eLogs = pkgs.writeShellApplication {
        name = "famedly-e2e-logs";
        runtimeInputs = with pkgs; [
          k3d
          kubectl
        ];
        text = commonEnv + builtins.readFile ./scripts/e2e-logs.sh;
      };

      e2eApps = [
        e2eUp
        e2eDown
        e2eRun
        e2eSeed
        e2eStatus
        e2eLogs
      ];

    in
    {
      options.famedly.standards.e2e = {
        enable = lib.mkEnableOption "k3d-based e2e testing with Argo CD";

        clusterName = lib.mkOption {
          type = lib.types.str;
          default = "e2e";
          description = "k3d cluster name. Change when running multiple clusters in parallel.";
        };

        registry = {
          name = lib.mkOption {
            type = lib.types.str;
            default = "k3d-e2e-registry.localhost";
            description = "k3d registry name. Must start with 'k3d-' for k3d to manage it.";
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = 5111;
            description = "Host port for the local OCI registry.";
          };
        };

        portForwards = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "k3d port mappings (format: 'hostPort:containerPort@loadbalancer').";
          example = [
            "8080:8080@loadbalancer"
            "8008:8008@loadbalancer"
          ];
        };

        chart = lib.mkOption {
          type = lib.types.either lib.types.path (lib.types.attrsOf lib.types.str);
          description = ''
            Helm chart source. Either a local Nix path or a Git reference:
              Local:  ../helm-charts/e2e-platform
              Git:    { repo = "https://..."; path = "e2e-platform"; rev = "..."; hash = "..."; }
          '';
        };

        values = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Helm values to pass to the chart (merged on top of chart defaults).";
        };

        namespace = lib.mkOption {
          type = lib.types.str;
          default = "default";
          description = "Kubernetes namespace for the chart deployment.";
        };

        readySelector = lib.mkOption {
          type = lib.types.str;
          default = "app.kubernetes.io/name=synapse";
          description = "kubectl label selector to wait for before running the seed script.";
        };

        readyTimeout = lib.mkOption {
          type = lib.types.str;
          default = "600s";
          description = "Timeout for pod readiness check.";
        };

        seed = {
          script = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Script executed after services are ready.
              Responsible for API calls, config adjustments, and writing .env.e2e.
            '';
          };
          runtimeInputs = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Packages available in the seed script's PATH (e.g. curl, jq).";
          };
          envFile = lib.mkOption {
            type = lib.types.str;
            default = ".env.e2e";
            description = "Path to write connection details for test runners.";
          };
        };

        observability = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Deploy OpenObserve for logs/metrics/traces (applied before platform services).";
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = 5080;
            description = "Host port for OpenObserve UI.";
          };
          otelPort = lib.mkOption {
            type = lib.types.int;
            default = 5081;
            description = "Host port for OpenObserve OTel gRPC endpoint.";
          };
        };

        testCommand = lib.mkOption {
          type = lib.types.str;
          default = "echo 'No testCommand configured'";
          description = ''
            Command executed by famedly-e2e (CI mode) after the environment is ready.
            Examples:
              "cargo nextest run -E 'test(e2e)' --features simple-client"
              "dart test test/e2e"
              "npm run test:e2e"
          '';
        };

        testFilterExpr = lib.mkOption {
          type = lib.types.str;
          default = "test(e2e)";
          description = "nextest filter expression used for automatic exclusion in nix flake check.";
        };

        extraManifests = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          description = "Additional Kubernetes manifests to apply before Argo Applications (Secrets, ConfigMaps, etc.).";
        };

        imagePullSecrets = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Name of the Kubernetes Secret.";
                };
                registry = lib.mkOption {
                  type = lib.types.str;
                  description = "Registry hostname (e.g. registry.famedly.net).";
                };
                username = lib.mkOption {
                  type = lib.types.str;
                  description = "Registry username.";
                };
                password = lib.mkOption {
                  type = lib.types.str;
                  description = "Environment variable name containing the registry password.";
                };
              };
            }
          );
          default = [ ];
          description = "Docker registry credentials for private images (e.g. registry.famedly.net).";
        };
      };

      config = lib.mkIf cfg.enable {
        # Expose all e2e apps as flake apps (nix run .#famedly-e2e, etc.)
        apps = lib.listToAttrs (
          map (app: {
            name = app.meta.mainProgram or app.pname or app.name;
            value = {
              type = "app";
              program = lib.getExe app;
            };
          }) e2eApps
        );

        # Add e2e tools to the shared devShell when devShell module is also enabled.
        famedly.standards.devShell.extraPackages = lib.mkIf (
          config.famedly.standards.devShell.enable or false
        ) (e2eApps ++ [ pkgs.k3d pkgs.kubectl pkgs.kubernetes-helm ]);

        # Auto-exclude e2e tests from nix flake check (uses mkDefault so consumers can override).
        famedly.standards.rust.checks.nextest.extraArgs = lib.mkIf (
          config.famedly.standards.rust.enable or false
        ) (lib.mkDefault "-E 'not ${cfg.testFilterExpr}'");
      };
    }
  );
}
