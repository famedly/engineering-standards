# Helm chart packaging helpers for e2e testing.
#
# Resolves chart sources (local path or Git repo) and packages them
# deterministically via `helm package` at Nix build time.
#
# Pre-vendoring requirement: Umbrella-Charts must commit their `charts/`
# subdirectory (pre-vendored subcharts via `helm dependency build`) so that
# packaging works without network access inside the Nix sandbox.

{ pkgs, lib }:
{
  # Resolve a chart source to a store path.
  # Accepts either:
  #   - a local Nix path:  ../helm-charts/e2e-platform
  #   - a Git reference:   { repo = "https://..."; path = "e2e-platform"; rev = "..."; hash = "..."; }
  resolveChartSource =
    chart:
    if builtins.isPath chart then
      # Nix path literal: ./path/to/chart
      chart
    else if builtins.isString chart && builtins.substring 0 1 chart == "/" then
      # Absolute path string: "${inputs.helm-charts}/e2e-platform" or store path
      chart
    else if builtins.isAttrs chart && chart ? rev then
      # Git reference: { repo = "..."; path = "..."; rev = "..."; hash = "..."; }
      "${builtins.fetchGit {
        url = chart.repo;
        rev = chart.rev;
        narHash = chart.hash;
        submodules = false;
      }}/${chart.path}"
    else
      throw "e2e.chart must be a Nix path, an absolute path string, or an attrset with { repo, path, rev, hash }";

  # Package a single chart directory into a .tgz derivation.
  # The result is a store path containing exactly one *.tgz file.
  packageChart =
    {
      chartSrc,
      name,
    }:
    pkgs.runCommand "helm-pkg-${name}"
      {
        nativeBuildInputs = [ pkgs.kubernetes-helm ];
      }
      ''
        cp -r ${chartSrc} chart
        chmod -R u+w chart
        cd chart

        # Use pre-vendored charts/ if present; skip network download.
        if [ -f Chart.lock ]; then
          helm dependency build --skip-refresh . || true
        fi

        mkdir -p "$out"
        helm package . --destination "$out"
      '';
}
