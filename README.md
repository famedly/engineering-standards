# engineering-standards

Nix flake module for Famedly repos. One input, options under `famedly.standards.*` and `famedly.github.workflows.*`, then `famedly-regen` writes configs and GitHub workflow YAML into your tree.

CI = `nix flake check`. Workflows are generated from Nix via [`github-actions-nix`](https://github.com/synapdeck/github-actions-nix) — no `workflow_call`.

---

## Quick start

```sh
nix flake init -t github:famedly/engineering-standards#dart   # or #rust, #flutter, #flutter-rust
nix flake update && nix run .#regenerateStandards && nix flake check
nix develop
```

Inside `nix develop`:

```sh
famedly-regen          # regenerate managed files
famedly-regen --dev    # same, with local engineering-standards checkout
famedly-check          # nix flake check -L
famedly-lint           # pre-commit run --all-files
famedly-lint --fix     # same, continue on errors
famedly-update         # update input + regenerate + check
famedly-help           # list commands
```

See **[docs/adopting.md](docs/adopting.md)** for existing repos, configuration reference, and migration.

---

## What it provides

| Feature | Output |
|---------|--------|
| `linting` | `analysis_options.yaml`, `deny.toml`, `pyproject.toml`, … |
| `preCommitHooks` | git hooks (typos, reuse, clippy, dart, ruff, …) |
| `infrastructure` | `.editorconfig`, `.github/dependabot.yml` |
| `devShell` | `famedly-*` CLI (see above) |
| `rules` | `.cursor/rules/…`, `CLAUDE.md` |
| Workflows | `ci`, `general-checks`, `dart-ci` (multi-package), `rust-ci`, `docker` (multi-arch/simple), `review-app`, `github-pages`, `hookd-deploy`, `release`, `publish-crate`, `publish-pub`, `docker-backend`, `docker-bake`, `ansible-ci`, `ai-review`, `fast-forward`, `add-to-project`, `update-engineering-standards` |
| `platform` | local k3d + Tilt dev environment (wraps `famedly-platform`) |
| `projects` | monorepo: per-folder lint/hooks/dependabot |

---

## Platform dev environment

Enable a local Famedly platform (k3d + Tilt) that builds your service image on every code change while all other services run from pre-built registry images.

```nix
perSystem = { ... }: {
  famedly.standards.platform = {
    enable = true;
    image = {
      name = "famedly-operator";   # must match the Helm subchart name
      chart = ./helm/famedly-operator;
    };
  };
};
```

Then start with `nix run .#famedly-platform-up` and tear down with `nix run .#famedly-platform-down`.

### All platform options

| Option | Default | Description |
|--------|---------|-------------|
| `image.name` | `null` | Helm subchart name — Tilt builds this image locally |
| `image.src` | `"."` | Docker build context (relative to repo root) |
| `image.build.docker` | `null` | Dockerfile path (default: `<src>/Dockerfile`) |
| `image.build.nix` | `null` | Nix flake package for container image (e.g. `"my-container"`) |
| `image.chart` | `null` | Local Helm chart dir — overrides the published subchart |
| `image.hotReload` | `[]` | Push file changes into the container without rebuild |
| `image.patch.cargo` | `{}` | Cargo `[patch]` overrides for local Rust dependency development |
| `extraImages` | `[]` | Additional local images (monorepo setups) |
| `chart` | pinned `helm-charts` | Platform umbrella chart source |
| `values` | `{}` | Additional Helm values |
| `ports` | 9310, 8080, 8008, 8282 | k3d port mappings |
| `testCommand` | — | CI mode: run after environment is ready |
| `extraManifests` | `[]` | Extra K8s manifests to apply before the chart |

### Hot-reload (frontends)

```nix
image.hotReload = [
  { from = "build/web"; to = "/usr/share/nginx/html"; }
];
```

### Cargo patch (Rust dependency override)

```nix
image.patch.cargo = {
  "https://github.com/famedly/zitadel-rust-client" = "../zitadel-rust-client";
};
```

See [`famedly-platform` README](https://github.com/famedly/famedly-platform) for full platform documentation.
