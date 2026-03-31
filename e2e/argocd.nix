# Argo CD helpers for e2e testing.
#
# Uses Argo CD Core Install (minimal footprint):
#   - Application Controller + CRDs only
#   - No UI server, no Dex, no Redis, no Notifications Controller
#   - ~2 Pods instead of 7
#
# Application CRs are generated as JSON manifests and placed in a
# directory derivation, which famedly-e2e-up applies via kubectl.

{ pkgs, lib }:
let
  argocdVersion = "2.14.11";
in
{
  # Pinned Argo CD Core Install manifest (fetched at eval time).
  # Replace the hash after a version bump by running:
  #   nix-prefetch-url https://raw.githubusercontent.com/argoproj/argo-cd/v<version>/manifests/core-install.yaml
  installManifest = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/argoproj/argo-cd/v${argocdVersion}/manifests/core-install.yaml";
    hash = "sha256-ymLlpCeGTWYAlY3tgcZI+oafkEuG20c4jcBOvmqqqG0=";
  };

  # Generate an Argo CD Application CR as a JSON string.
  # Parameters:
  #   name        - Application name (also used as chart name and release name)
  #   registryUrl - OCI registry URL, e.g. "localhost:5111"
  #   chartVersion - Exact chart version from Chart.yaml
  #   namespace   - Target deployment namespace
  #   values      - Helm values attrset (merged on top of chart defaults)
  #   annotations - Extra metadata annotations (e.g. sync-wave)
  makeApplication =
    {
      name,
      registryUrl,
      chartVersion,
      namespace ? "default",
      values ? { },
      annotations ? { },
    }:
    builtins.toJSON {
      apiVersion = "argoproj.io/v1alpha1";
      kind = "Application";
      metadata = {
        inherit name;
        namespace = "argocd";
        annotations = annotations;
      };
      spec = {
        project = "default";
        destination = {
          server = "https://kubernetes.default.svc";
          namespace = namespace;
        };
        source = {
          repoURL = "oci://${registryUrl}/helm";
          chart = name;
          targetRevision = chartVersion;
          helm = {
            releaseName = name;
            valuesObject = values;
          };
        };
        syncPolicy = {
          automated = {
            prune = true;
            selfHeal = true;
          };
          syncOptions = [ "CreateNamespace=true" ];
        };
      };
    };

  # Extract the version field from a packaged chart's Chart.yaml.
  # Used to set targetRevision deterministically (no wildcards).
  extractChartVersion =
    chartPkg:
    pkgs.runCommand "chart-version"
      {
        nativeBuildInputs = [ pkgs.kubernetes-helm pkgs.jq ];
      }
      ''
        tgz=$(ls ${chartPkg}/*.tgz | head -1)
        helm show chart "$tgz" | grep '^version:' | awk '{print $2}' > "$out"
      '';

  # Build a directory containing all Application CR YAML files.
  # Each file is named <app-name>.yaml.
  makeApplicationsDir =
    apps:
    pkgs.runCommand "argo-applications"
      { }
      (
        ''
          mkdir -p "$out"
        ''
        + lib.concatStrings (
          lib.mapAttrsToList (name: content: ''
            echo ${lib.escapeShellArg content} > "$out/${name}.yaml"
          '') apps
        )
      );
}
