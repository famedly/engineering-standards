# engineering-standards

Nix-first **defaults for Famedly repos**: one flake input, options under `famedly.standards.*` and `famedly.github.workflows.*`, then `nix run .#regenerateStandards` writes configs and GitHub workflows into your tree. CI is "install Nix → `nix flake check`"; additional workflows are **generated directly from Nix** via [`github-actions-nix`](https://github.com/synapdeck/github-actions-nix).

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

**Existing repo:** add input `github:famedly/engineering-standards`, `imports = [ inputs.engineering-standards.flakeModules.default ];`, set `famedly.standards` + `famedly.github.workflows` (see [docs/adopting.md](docs/adopting.md)), then the same `regenerateStandards` + `flake check`.

---

## What it does

| You enable | You get (examples) |
|------------|-------------------|
| `rules` | `.cursor/rules/…`, `CLAUDE.md` |
| `linting` | language lint configs (`analysis_options.yaml`, `deny.toml`, …) |
| `preCommitHooks` | git hooks via git-hooks.nix; also runs as part of `nix flake check` |
| `infrastructure` | `.editorconfig`, Dependabot |
| `famedly.github.workflows.ci` | `.github/workflows/ci.yml` → Nix in CI |
| `famedly.github.workflows.*` | complete workflow YAML generated from Nix definitions |
| `famedly.github.workflows.update-engineering-standards` | PR bot: bump input + regenerate |
| `projects` | monorepo: per-folder lint/hooks/deps |

Details and migration steps: **[docs/adopting.md](docs/adopting.md)**.

---

## This repository

- **`nix/modules/`** — flake module consumers import.
- **`nix/modules/workflows/`** — workflow generation system:
  - `default.nix` — auto-discovery orchestrator with `builtins.readDir`, `importApply`, and `types.submoduleWith`.
  - `lib.nix` — shared helpers (`ghExpr`, `mkNixInstallStep`, `mkRustPrepareStep`, `mkDartPrepareStep`, `sharedValueNames`).
  - `definitions/*.nix` — one file per workflow (19 definitions), each a self-contained submodule.
- **`nix/action-versions-data.nix`** — SHA-pinned action versions for remaining GitHub Actions.
- **`nix/templates/`** — `nix flake init` templates.

**Maintainers:** `nix run .#regenerateStandards` refreshes generated workflows (and dogfooded `ci.yml`); `nix flake check` must pass (includes workflow consistency checks).

---

## Extra

- **Dart lints package:** `linting/dart-package` → dependency `engineering_standards_lints` (see [docs/adopting.md](docs/adopting.md#dart-lints)).
- **Changelog:** [CHANGELOG.md](CHANGELOG.md).
- **Workflow smoke tests:** separate repo `engineering-standards-workflow-smoke` (if you use it locally).
