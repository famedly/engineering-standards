---
name: update-user-docs
description: Updates Famedly engineering-standards user-facing documentation (`README.md`, `docs/adopting.md`, `docs/README.md`, `CHANGELOG.md`) to match the current state of `famedly.standards.*`, `famedly.github.workflows.*`, linting scopes, and pre-commit hooks. Use when adding or renaming options, workflows, hooks or linting scopes, when the user asks to update or audit the docs, or when documentation drift is suspected.
---

# Update user-facing documentation

The user-facing documentation surface is small and authoritative. There is exactly one canonical reference ([`docs/adopting.md`](../../../docs/adopting.md)); everything else points at it. Drift is prevented by re-deriving the canonical lists from source files before editing.

## Surface owned by this skill

| File | Purpose |
|------|---------|
| [`README.md`](../../../README.md) | Project overview, quick start, "What it provides" table. |
| [`docs/adopting.md`](../../../docs/adopting.md) | Canonical reference: `famedly.standards.*` table, `famedly.github.workflows.*` table, pre-commit hooks table, monorepo `projects.*` options, troubleshooting. |
| [`docs/README.md`](../../../docs/README.md) | Doc index. |
| [`CHANGELOG.md`](../../../CHANGELOG.md) | Keep-a-Changelog format. Only user-facing behaviour changes. |

## Drift audit (sources of truth)

Before editing, run the audit relevant to your change. Each item lists the source-of-truth enumeration and the doc location it must match.

| Doc location | Source of truth | Enumerate with |
|--------------|-----------------|----------------|
| Workflow table in `docs/adopting.md` | `nix/modules/workflows/definitions/*.nix` | `ls nix/modules/workflows/definitions/*.nix` |
| `famedly.standards.*` option table | `lib.mkOption` / `lib.mkEnableOption` declarations under `nix/modules/` (excluding `_internal.*`) | `rg -n 'mkOption\|mkEnableOption' nix/modules/` |
| Pre-commit hooks table | Hook definitions in `nix/modules/pre-commit-hooks.nix` | `rg -n '\.enable = true\|<hook-id> = \{' nix/modules/pre-commit-hooks.nix` |
| Linting scope rows | Sub-directories of `linting/` | `ls -1 linting/` |
| Templates listed in `README.md` quick-start | Sub-directories of `nix/templates/` | `ls -1 nix/templates/` |

## Procedure

1. Identify which sources changed: `git diff --name-only $(git merge-base HEAD origin/main)..HEAD`.
2. Run the relevant drift-audit row(s) above and diff the enumeration against the doc table. Note any pre-existing gaps.
3. Edit only the affected rows / paragraphs. Do not restructure unrelated sections.
4. If the change is user-facing, add a `CHANGELOG.md` entry under the next unreleased section (create one if missing). Do not bump versions — releases are a separate workstream.
5. If the same change also added, removed or renamed a project skill, follow [`../update-agent-instructions/SKILL.md`](../update-agent-instructions/SKILL.md) in the same change.

## Conventions

- Markdown only, no HTML. Tables for option / workflow / hook enumerations.
- British English (matches existing prose in `docs/adopting.md`).
- File paths: markdown links in prose (`[docs/adopting.md](docs/adopting.md)`); identifiers like `famedly.standards.*` or `flake.nix` in backticks.
- Additive edits unless the user explicitly asked for restructuring.
- Do not duplicate content between `README.md` and `docs/adopting.md` — `README.md` summarises and links, `docs/adopting.md` enumerates.

## Verification

- Re-run every drift-audit command above for the affected category. Each enumeration MUST be a subset of (and ideally equal to) the corresponding doc table.
- `nix flake check -L` should still pass — doc-only changes do not affect derivations, but a green check confirms nothing else regressed.
