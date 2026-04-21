---
name: add-linting-config
description: Adds or updates a language linting configuration distributed by Famedly engineering-standards. Use when adding a file under `linting/<lang>/` (for example `clippy.toml`, `analysis_options.yaml`, `ruff.toml`, `eslint.config.base.mjs`), when extending `famedly.standards.linting.*`, or when introducing a new language scope.
---

# Add or update a linting config

Linting configs are raw files that get copied verbatim from `linting/<lang>/` into the consumer repo root by [`nix/modules/linting.nix`](../../../nix/modules/linting.nix). The module auto-discovers every file in the matching directory — there is no per-file registration step.

## Where to put files

| Scope | Directory | Enable flag |
|-------|-----------|-------------|
| Dart | `linting/dart/` | `famedly.standards.linting.dart` |
| Flutter | `linting/flutter/` | `famedly.standards.linting.flutter` |
| Rust | `linting/rust/` | `famedly.standards.linting.rust` |
| Python | `linting/python/` | `famedly.standards.linting.python` |
| TypeScript | `linting/typescript/` | `famedly.standards.linting.typescript` |
| Dart package (in `dart-package/`) and Flutter package (in `flutter-package/`) | `linting/dart-package/`, `linting/flutter-package/` | (consumed by the dart-package / flutter-package modules) |
| Editorconfig | `linting/editorconfig` (a single file, not a directory) | `famedly.standards.infrastructure.editorconfig` |
| REUSE | `linting/reuse/REUSE.toml` | `famedly.standards.preCommitHooks.fossHooks.enable` |

## File-naming convention (initialOnly)

[`nix/modules/linting.nix`](../../../nix/modules/linting.nix) treats a file literally named `analysis_options.yaml` as `initialOnly` — it is created on first regen and then left alone so the consumer can edit it. Everything else is overwritten on every regen.

If you need a Dart/Flutter file that is always managed alongside the user-editable one, name it `analysis_options.standards.yaml` (the existing pattern). For other languages, simply do not name your file `analysis_options.yaml`.

## Adding a new language scope

1. Create `linting/<lang>/` and drop the config files.
2. Extend the `famedly.standards.linting` options in [`nix/modules/linting.nix`](../../../nix/modules/linting.nix), mirroring the existing `dart` / `rust` / `python` boolean pattern, and add the corresponding `<lang>Files = lib.optionals cfg.<lang> (filesForScope "<lang>");` line plus the concat in `config.famedly.standards._internal.managedFiles`.
3. If the language also needs a pre-commit hook group, follow the [add-pre-commit-hook-group](../add-pre-commit-hook-group/SKILL.md) skill in the same change.
4. Update user-facing documentation (`famedly.standards.*` and linting tables in `docs/adopting.md`) by following [`../update-user-docs/SKILL.md`](../update-user-docs/SKILL.md).

## Updating an existing config

Just edit the file under `linting/<lang>/`. No Nix changes are needed unless you renamed the destination, in which case verify the consumer-side filename via the `dest = name;` mapping in `nix/modules/linting.nix`.

## Verification

```sh
nix flake check -L
nix flake show
```

For behaviour-altering changes, also run `nix run .#regenerateStandards` against a template under `nix/templates/` and inspect the diff.
