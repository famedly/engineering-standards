# Adopting engineering-standards

## Prerequisites

Install [Nix](https://nixos.org/download/) and enable flakes, e.g. in `nix.conf`:

```ini
experimental-features = nix-command flakes
```

## Day-to-day model

1. Edit **`flake.nix`** — `famedly.standards` and `famedly.github.workflows` options.
2. Run **`nix run .#regenerateStandards`** — writes tracked files (workflows, rules, lint configs, …) and removes any files that belonged to features you just disabled.
3. Run **`nix flake check`** locally; commit outputs + lockfile (including `.engineering-standards-manifest`).

Do not hand-edit files marked as managed by the module; change Nix and regenerate.

> **File cleanup:** `regenerateStandards` maintains `.engineering-standards-manifest` in the repo root. On each run it removes files from the previous generation that are no longer managed (e.g. after setting `rules.enable = false`). Commit the manifest alongside generated files so cleanup works correctly on the next run.

## New repository

```sh
nix flake init -t github:famedly/engineering-standards#rust   # or dart, flutter, flutter-rust
nix flake update
nix run .#regenerateStandards
nix flake check
```

Templates live under `nix/templates/` if you prefer copy-paste.

## Existing repository

1. Add the flake input and import the module:

```nix
inputs.engineering-standards.url = "github:famedly/engineering-standards";

# in outputs:
imports = [ inputs.engineering-standards.flakeModules.default ];
```

2. Under `perSystem`, set `famedly.standards` and `famedly.github.workflows`:

```nix
famedly.standards = {
  rules.enable = true;
  linting = { enable = true; rust = true; };   # or dart / flutter
  hooks = { enable = true; rust = true; };
  checks.enable = true;
  infrastructure = { editorconfig = true; dependabot = true; };
};

famedly.github.workflows = {
  ci.enable = true;
  general-checks.enable = true;
  rust-ci.enable = true;             # Rust CI with tests, coverage, typos
  # publish-crate.enable = true;     # Crate publishing
  # dart-ci.enable = true;           # Dart/Flutter CI
  # docker.enable = true;            # Docker build & push
  # release.enable = true;           # GitHub Releases via gh CLI
};
```

3. `nix flake lock`, `nix run .#regenerateStandards`, `nix flake check`, commit.

4. Remove **old** workflows that duplicated CI (org-specific `uses: famedly/...` stacks, `general.yml`, legacy sync workflows, etc.) so you do not run two systems at once.

## Staying up to date

Enable:

```nix
famedly.github.workflows.update-engineering-standards.enable = true;
```

Regenerate once so `.github/workflows/update-engineering-standards.yml` appears. That workflow can run on a schedule, on **`repository_dispatch`**, or manually.

Consumers pin the **engineering-standards** input in `flake.lock`. Workflows are generated as complete YAML — no `workflow_call` indirection.

## Monorepos

Use `famedly.standards.projects` for multiple roots (e.g. `backend/` Rust + `frontend/` Flutter). Each entry gets scoped lint files, Dependabot paths, and hooks. Template: `nix flake init -t github:famedly/engineering-standards#flutter-rust`.

Avoid turning on the **same** language both at the root and inside `projects` — you would duplicate configs.

## GitHub Actions layout

Workflows are **generated entirely from Nix** using [`github-actions-nix`](https://github.com/synapdeck/github-actions-nix). Each workflow definition lives in `nix/modules/workflows/definitions/<name>.nix` as a self-contained Nix submodule with its own options and `enable` flag.

- **No `workflow_call`** — each generated `.github/workflows/<name>.yml` is a complete, standalone workflow.
- **Nix-first tooling** — CLI tools (typos, cargo-deny, black, dart, flutter, nushell) are installed at CI time via `nix profile install` from the flake's pinned nixpkgs, rather than through third-party GitHub Actions.
- **Third-party actions** that remain (checkout, cache, Docker, Codecov, Cachix, Sequoia PGP) are SHA-pinned in `nix/action-versions-data.nix`.

Available workflows (all under `famedly.github.workflows`):

| Area | Workflow options |
|------|-----------------|
| CI & Nix | `ci` |
| Git hygiene / org | `general-checks`, `authenticate-commits`, `fast-forward`, `add-to-project`, `ai-review`, `release` |
| Rust | `rust-ci` (tests, coverage, typos, cargo-deny), `publish-crate` |
| Dart / Flutter | `dart-ci` (sdk option: `"flutter"` or `"dart"`), `publish-pub` |
| Docker | `docker`, `docker-backend`, `docker-bake` |
| Deployment | `github-pages`, `review-app` |
| Ansible | `ansible-ci` |
| Maintenance | `update-engineering-standards`, `update-openpgp-policy` |

### Workflow helper library

`nix/modules/workflows/lib.nix` provides shared functions used across definitions:

| Helper | Purpose |
|--------|---------|
| `ghExpr`, `ghVar`, `ghSecret`, `ghEnv` | Produce GitHub Actions `${{ }}` expressions without Nix escaping issues |
| `nixSetupStep` | `cachix/install-nix-action` step |
| `mkNixInstallStep` | Install any nixpkgs package via `nix profile install`, pinned to the flake's nixpkgs rev |
| `mkRustPrepareStep` | Inline Rust environment setup (SSH, Cargo, private registry) |
| `mkDartPrepareStep` | Inline Dart/Flutter SSH setup for private dependencies |
| `ciConcurrency` | Reusable concurrency block (cancel in-progress on same branch) |
| `sharedValueNames` | Centralized registry of GitHub secrets and variables as camelCase maps |

## Dart lints

If you use the shared Dart package:

```yaml
dev_dependencies:
  engineering_standards_lints:
    git:
      url: https://github.com/famedly/engineering-standards.git
      path: linting/dart-package
```

## Troubleshooting

- **`nix` / flakes errors** — confirm flakes are enabled; run `nix flake lock` after changing inputs.
- **CI differs from laptop** — CI runs `nix flake check -L`; keep checks defined in your flake.
- **Workflow drift in *this* repo** — run `nix run .#regenerateStandards` and commit; `nix flake check` enforces it.

## Legacy replacements (orientation)

| Old | New |
|-----|-----|
| Scattered `famedly/*-workflows` repos | `famedly.github.workflows.*` — complete workflow generation from Nix |
| `workflow_call` reusable workflows | Standalone generated YAML per workflow |
| `hustcer/setup-nu`, `crate-ci/typos`, `embarkstudios/cargo-deny`, `softprops/action-gh-release`, `famedly/black`, `dart-lang/setup-dart`, `subosito/flutter-action` | Nix-installed tools via `nix profile install` |
| `.github/actions/rust-prepare/` composite action | `mkRustPrepareStep` inline helper in `lib.nix` |
| `.github/actions/dart-prepare/` composite action | `mkDartPrepareStep` inline helper in `lib.nix` |
| `frontend-ci-templates` Dart lints | `linting/dart-package` + `famedly.standards.dart` |
| Per-repo YAML-only standards | `flake.nix` + regenerate |
