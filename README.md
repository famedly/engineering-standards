# engineering-standards

Nix-first **defaults for Famedly repos**: one flake input, options under `famedly.standards.*`, then `nix run .#regenerateStandards` writes configs and GitHub workflows into your tree. CI is “install Nix → `nix flake check`”; extra jobs call **reusable workflows** from this repo.

**In one sentence:** configure standards in `flake.nix`, regenerate files, commit them; stay current with `flake.lock` and an optional update workflow.

---

## Quick start

**New repo** (empty dir or after `git init`):

```sh
nix flake init -t github:famedly/engineering-standards#rust      # or #dart, #flutter, #flutter-rust
nix flake update
nix run .#regenerateStandards
nix flake check
```

**Existing repo:** add input `github:famedly/engineering-standards`, `imports = [ inputs.engineering-standards.flakeModules.default ];`, set `famedly.standards` (see [docs/adopting.md](docs/adopting.md)), then the same `regenerateStandards` + `flake check`.

---

## What it does

| You enable | You get (examples) |
|------------|-------------------|
| `rules` | `.cursor/rules/…`, `CLAUDE.md` |
| `linting` / `hooks` | language configs, `.pre-commit-config.yaml` |
| `checks` | hooks into `nix flake check` |
| `infrastructure` | `.editorconfig`, Dependabot |
| `ci` | `.github/workflows/ci.yml` → Nix in CI |
| `workflows.*` | thin callers → reusable workflows **in this repo** |
| `updateWorkflow` | PR bot: bump input + regenerate |
| `projects` | monorepo: per-folder lint/hooks/deps |

Details and migration steps: **[docs/adopting.md](docs/adopting.md)**.

---

## This repository

- **`nix/modules/`** — flake module consumers import.
- **`nix/modules/ci-workflow.nix`** (via root flake `famedly.standards.ci`) + **`nix/action-versions-data.nix`** — `.github/workflows/ci.yml`.
- **`nix/workflow-sources/`** + **`nix/action-versions-data.nix`** — remaining reusable workflow YAML under `.github/workflows/`.
- **`nix/templates/`** — `nix flake init` templates.

**Maintainers:** `nix run .#regenerateStandards` refreshes generated workflows (and dogfooded `ci.yml`); `nix flake check` must pass (includes workflow consistency checks).

---

## Extra

- **Dart lints package:** `linting/dart-package` → dependency `engineering_standards_lints` (see [docs/adopting.md](docs/adopting.md#dart-lints)).
- **Changelog:** [CHANGELOG.md](CHANGELOG.md).
- **Workflow smoke tests:** separate repo `engineering-standards-workflow-smoke` (if you use it locally).
