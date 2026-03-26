# Adopting engineering-standards

## Prerequisites

Install [Nix](https://nixos.org/download/) and enable flakes, e.g. in `nix.conf`:

```ini
experimental-features = nix-command flakes
```

## Day-to-day model

1. Edit **`flake.nix`** — `famedly.standards` options.
2. Run **`nix run .#regenerateStandards`** — writes tracked files (workflows, rules, lint configs, …).
3. Run **`nix flake check`** locally; commit outputs + lockfile.

Do not hand-edit files marked as managed by the module; change Nix and regenerate.

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

2. Under `perSystem`, set `famedly.standards` — start small, expand later:

```nix
famedly.standards = {
  rules.enable = true;
  linting = { enable = true; rust = true; };   # or dart / flutter
  hooks = { enable = true; rust = true; };
  checks.enable = true;
  infrastructure = { editorconfig = true; dependabot = true; };
  ci.enable = true;
  workflows.conventionalCommits = true;
};
```

3. `nix flake lock`, `nix run .#regenerateStandards`, `nix flake check`, commit.

4. Remove **old** workflows that duplicated CI (org-specific `uses: famedly/...` stacks, `general.yml`, legacy sync workflows, etc.) so you do not run two systems at once.

## Staying up to date

Enable:

```nix
famedly.standards.updateWorkflow.enable = true;
```

Regenerate once so `.github/workflows/update-engineering-standards.yml` appears. That workflow can run on a schedule, on **`repository_dispatch`** (e.g. when this standards repo pushes to `main` via the GitHub App), or manually. For how the GitHub App relates to this flow, see **[github-app.md](github-app.md)**.

Consumers pin the **engineering-standards** input in `flake.lock`. Reusable workflow **callers** use `famedly.standards.workflowRef` (often a floating major tag like `v1`); breaking workflow changes ship as a new major tag.

## Monorepos

Use `famedly.standards.projects` for multiple roots (e.g. `backend/` Rust + `frontend/` Flutter). Each entry gets scoped lint files, Dependabot paths, and hooks. Template: `nix flake init -t github:famedly/engineering-standards#flutter-rust`.

Avoid turning on the **same** language both at the root and inside `projects` — you would duplicate configs.

## GitHub Actions layout (mental model)

- **Your repo** gets small **caller** workflows under `.github/workflows/` (names like `publish-crate.yml`, `general-checks.yml`).
- They **`workflow_call`** into **`famedly/engineering-standards`** (reusable YAML in *this* repo: `rust-ci.yml`, `general-checks.yml`, `infra-docker.yml`, …).
- Third-party actions inside those reusables are **SHA-pinned** here; pins are maintained via `nix/workflow-sources/` and `nix/action-versions-data.nix`.

To see which `famedly.standards.workflows` option generates which file, open `nix/modules/workflows/*.nix`. Rough map:

| Area | Options (all under `famedly.standards.workflows`) |
|------|---------------------------------------------------|
| Git hygiene / org | `conventionalCommits`, `authenticateCommits`, `fastForward`, `addToProject`, `updateOpenpgpPolicy`, `aiReview`, `release`, `reuse` |
| Rust | `rustCi`, `rustPublish` |
| Dart / Flutter | `dartCi`, `dartPublish`, `dartReviewApp` |
| Shipping | `docker`, `dockerBackend`, `dockerBake`, `githubPages` |
| Ansible | `ansible` |

Separate from that table: **`ci.enable`** → root `ci.yml` (Nix only). **`updateWorkflow.enable`** → standards bump automation.

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

| Old | New idea |
|-----|----------|
| Scattered `famedly/*-workflows` repos | `famedly.standards.checks` + reusable workflows here |
| `frontend-ci-templates` Dart lints | `linting/dart-package` + `famedly.standards.dart` |
| Per-repo YAML-only standards | `flake.nix` + regenerate |
