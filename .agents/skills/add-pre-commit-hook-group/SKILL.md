---
name: add-pre-commit-hook-group
description: Adds a new pre-commit hook or hook group to the Famedly engineering-standards distribution. Use when extending `famedly.standards.preCommitHooks.*`, when adding a hook in `nix/modules/pre-commit-hooks.nix`, or when adding language-specific lint or format hooks (clippy, rustfmt, dart format, ruff, etc.).
---

# Add a pre-commit hook (group)

All hooks live in [`nix/modules/pre-commit-hooks.nix`](../../../nix/modules/pre-commit-hooks.nix) and run via `git-hooks.nix`. The same definition powers both the local `nix develop` shellHook and the CI `pre-commit` derivation, so each hook is the single source of truth.

## Single hook vs language group

- **Base hooks** (always on when `preCommitHooks.enable = true`) live in the unconditional attribute set: `fix-byte-order-marker`, `check-yaml`, `typos`, `nixfmt-rfc-style`, etc. Add to that block for cross-language hooks.
- **Language groups** are gated on `cfg.<lang>Hooks.enable`. Each group MUST come in two flavours:
  1. A root-level variant gated on `cfg.<lang>Hooks.enable` (the existing `clippy` / `rustfmt` / `dart-format` / `ruff-check` blocks).
  2. A monorepo-scoped variant produced by `scoped<Lang>Hooks` and gated on `<lang>Projects != {}`.
  Mirror the existing Rust / Dart / Python pairs — do not ship a hook that only works at the repo root.

## Required conventions

- **Pin tool entries to absolute Nix store paths.** Use `${dartBin}`, `${rustfmtBin}`, `${cargoClippyBin}`, `${cargoBin}`, `${lib.getExe pkgs.ruff}`. Bare `cargo`/`dart` entries break under `+toolchain` / PATH ambiguity. The toolchain bindings are defined near the top of `pre-commit-hooks.nix`.
- **Set `pass_filenames = false`** for whole-workspace checks (clippy, dart analyze, dart_code_linter), otherwise pre-commit re-invokes the tool per file.
- **Set `types = [ "<lang>" ]`** so the hook only fires on relevant files.
- **Restrict to the project directory in monorepo variants** via `files = "^${dir}/"` (see how `scopedRustHooks` / `scopedDartHooks` build `filesAttr`).

## Skip lists

Per-project hook IDs MUST be added to `<lang>HookIdsToSkip`. The `pre-commit` `checks.*` derivation skips those IDs (`SKIP=…` env var) so CI does not try to run a project-scoped hook outside its directory. Look at `dartHookIdsToSkip` / `rustHookIdsToSkip` and extend them when you add a new scoped hook ID.

## Tooling availability

- If the hook needs a tool that is not already provided by the dev shell, add the package to `devShells.famedly-standards` in [`nix/modules/devshell.nix`](../../../nix/modules/devshell.nix). The CI hook derivation reuses the same toolset.
- If the tool ships with `git-hooks.nix`, prefer the built-in definition (`clippy.enable = true`, `rustfmt.enable = true`, `dart-format.enable = true`, `reuse.enable = true`, …) and only override `entry`/`settings` where necessary.

## Options + docs

- Add an `<lang>Hooks.enable` option (and any tunables) inside `options.famedly.standards.preCommitHooks`. Default to `false`.
- Update user-facing documentation (pre-commit hooks table in `docs/adopting.md`) by following [`../update-user-docs/SKILL.md`](../update-user-docs/SKILL.md).

## Verification

```sh
nix flake check -L          # builds the `pre-commit` derivation; runs every hook
nix develop -c famedly-lint # interactive feedback while iterating
```

Then enable the new option in a template under [`nix/templates/`](../../../nix/templates) (or this repo) and re-run the checks to confirm both root and monorepo variants behave correctly.
