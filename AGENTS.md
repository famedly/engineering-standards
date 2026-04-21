# AGENTS.md

Vendor-neutral instructions for AI/coding agents working **inside this repository**.

User-facing documentation for *consumer* repos that adopt these standards lives in [README.md](README.md) and [docs/adopting.md](docs/adopting.md). This file is exclusively about modifying *this* repo.

## 1. Repository purpose

`engineering-standards` is the source-of-truth Nix flake distribution for Famedly's engineering standards. It exposes a `flake-parts` module that consumer repos import, configures via `famedly.standards.*` and `famedly.github.workflows.*`, and then materialises into their working tree via `nix run .#regenerateStandards`. CI in any consumer repo is just `nix flake check`.

What ships from here:

- Linting configurations under [linting/](linting) (Dart, Flutter, Rust, Python, TypeScript, editorconfig, REUSE).
- Pre-commit hooks via [`nix/modules/pre-commit-hooks.nix`](nix/modules/pre-commit-hooks.nix) (`git-hooks.nix`).
- GitHub Actions workflows generated from [`nix/modules/workflows/definitions/`](nix/modules/workflows/definitions) via [`synapdeck/github-actions-nix`](https://github.com/synapdeck/github-actions-nix) — no `workflow_call` reusable workflows.
- Templates for `nix flake init -t` under [`nix/templates/`](nix/templates).
- Placeholder AI rules under [`ai-rules/`](ai-rules) wired up via [`nix/modules/rules.nix`](nix/modules/rules.nix).

## 2. Layout map

| Path | Purpose |
|------|---------|
| [`flake.nix`](flake.nix) | Entry point. Dogfoods itself: enables `famedly.standards.preCommitHooks` and `famedly.github.workflows.ci`. |
| [`nix/modules/`](nix/modules) | `flake-parts` modules: `default.nix`, `linting.nix`, `infrastructure.nix`, `devshell.nix`, `rules.nix`, `dart.nix`, `rust.nix`, `projects.nix`, `pre-commit-hooks.nix`, `compat.nix`, `action-versions.nix`. |
| [`nix/modules/workflows/`](nix/modules/workflows) | Workflow plumbing: `default.nix` (auto-discovers definitions), `lib.nix`, `definitions/<name>.nix` (one file per workflow, name = filename). |
| [`linting/<lang>/`](linting) | Raw config files copied verbatim into consumer repo roots by `nix/modules/linting.nix`. |
| [`nix/templates/{rust,dart,flutter,flutter-rust}/`](nix/templates) | `nix flake init -t` targets and canonical examples of consumer config. |
| [`nix/packages/`](nix/packages) | Dart / Flutter SDK derivations + `update-sdk-versions.py`. |
| [`nix/checks/`](nix/checks), [`nix/tests/default.nix`](nix/tests/default.nix) | Derivations evaluated by `nix flake check`. |
| [`ai-rules/{global,rust,dart}/`](ai-rules) | Placeholder `.mdc` files. The rules module currently emits a placeholder `CLAUDE.md` into *consumer* repos when `rules.enable = true`. |
| [`docs/adopting.md`](docs/adopting.md) | Sole user-facing reference. Keep in sync with every option / workflow / hook change. |
| [`.engineering-standards-manifest`](.engineering-standards-manifest) | List of files this repo currently materialises into itself. Rewritten by `regenerateStandards`. |

## 3. Golden rules

- **Never hand-edit a generated file.** Every entry in `.engineering-standards-manifest` (currently just `.github/workflows/ci.yml`) is rewritten by `nix run .#regenerateStandards`. The `ci-workflow-dogfood` check in `flake.nix` fails on drift.
- **All workflow YAML is generated** from `nix/modules/workflows/definitions/<name>.nix` via `github-actions-nix`. Do not write raw `.github/workflows/*.yml`. Do not introduce `workflow_call` reusable workflows; use `triggerMode = "workflowRun"` for cross-workflow triggering.
- **SHA-pin every third-party action.** See [`nix/action-versions-data.nix`](nix/action-versions-data.nix) and [`nix/modules/action-versions.nix`](nix/modules/action-versions.nix). Never use floating `@v4` tags.
- **Document every new option** under `famedly.standards.*` or `famedly.github.workflows.*` by updating the tables in [`docs/adopting.md`](docs/adopting.md) in the same change.
- **Register every new managed file** by pushing onto `famedly.standards._internal.managedFiles` (`{ src; dest; initialOnly?; }`). That list is the only thing `regenerateStandards` walks for both writes and cleanup.
- **Templates must keep working.** Any breaking option rename requires corresponding edits in [`nix/templates/*/flake.nix`](nix/templates).
- **Do not touch `flake.lock` by hand.** If an input bump is genuinely needed, run `nix flake update <input>`.
- **This repo is Nix-only.** Do not invoke `cargo`, `dart`, `pub`, `pip`, `npm` directly — go through the dev shell or via Nix-built derivations.

## 4. Change recipes (Agent Skills)

Recurring tasks are captured as project-scoped Agent Skills under [`.agents/skills/`](.agents/skills). For any of these tasks, read and follow the matching skill rather than improvising. Skills are auto-discoverable by their frontmatter `description`; this table is the human-readable index.

| Task | Skill |
|------|-------|
| Add a new GitHub workflow definition | [`.agents/skills/add-github-workflow/SKILL.md`](.agents/skills/add-github-workflow/SKILL.md) |
| Add or update a linting config (`linting/<lang>/…`) | [`.agents/skills/add-linting-config/SKILL.md`](.agents/skills/add-linting-config/SKILL.md) |
| Add a pre-commit hook or hook group | [`.agents/skills/add-pre-commit-hook-group/SKILL.md`](.agents/skills/add-pre-commit-hook-group/SKILL.md) |
| Change this repo's own (dogfooded) CI workflow | [`.agents/skills/update-self-ci-workflow/SKILL.md`](.agents/skills/update-self-ci-workflow/SKILL.md) |
| Update user-facing documentation (`README.md`, `docs/adopting.md`, `CHANGELOG.md`) | [`.agents/skills/update-user-docs/SKILL.md`](.agents/skills/update-user-docs/SKILL.md) |
| Update agent instructions (`AGENTS.md`, `CLAUDE.md`, any `SKILL.md`) | [`.agents/skills/update-agent-instructions/SKILL.md`](.agents/skills/update-agent-instructions/SKILL.md) |

## 5. Verification (mandatory before finishing)

Run, in order:

1. `nix run .#regenerateStandards` — only if a module that emits managed files was touched. Commit any resulting diff in the same change.
2. `nix flake check -L` (or `nix develop -c famedly-check`). Runs `statix`, `deadnix`, `nix-modules-parse`, `ci-workflow-dogfood`, the `nix/tests/default.nix` evaluation tests, the `pre-commit` hook suite, and `treefmt`.
3. `nix develop -c famedly-lint` — fast hook-only feedback while iterating.
4. `nix flake show` — confirm new packages, apps, checks, and workflows appear.

## 6. Dev shell tools

`nix develop` provides `nil`, `nixfmt`, `prettier`, `statix`, `deadnix`, and `nix-output-monitor`. Formatting is driven by `treefmt-nix` (nixfmt-rfc-style + prettier). Do not introduce additional formatters.

## 7. Commit hygiene

- Use Conventional Commits, matching the existing [`CHANGELOG.md`](CHANGELOG.md) style (`feat:`, `fix:`, `chore:`, …).
- Do not bundle unrelated `.engineering-standards-manifest` or generated YAML changes into feature commits — those files should only move when the Nix module producing them changes.
- Do not commit `.claude/settings.local.json` (already in [`.gitignore`](.gitignore)).

## 8. What NOT to do

- Edit any file that starts with `# This file is automatically generated from Nix configuration.`
- Add floating GitHub Action versions (always SHA-pin via `action-versions-data.nix`).
- Bypass `famedly.standards._internal.managedFiles` when emitting files from a module.
- Hand-roll `workflow_call` reusable workflows.
- Run `cargo` / `dart` / `pub` directly in this repo.
- Enable `famedly.standards.preCommitHooks.fossHooks` for *this* repo — it is intentionally disabled in [`flake.nix`](flake.nix) (REUSE compliance is a consumer concern, not an engineering-standards-repo concern).
- Fill in [`ai-rules/*/placeholder.mdc`](ai-rules) as a side-effect of unrelated work — those are consumer-shipped rules and a separate workstream.
