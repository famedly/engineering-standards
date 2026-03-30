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
| `projects` | monorepo: per-folder lint/hooks/dependabot |
