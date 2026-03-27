# Adopting engineering-standards

## Table of contents

1. [Prerequisites](#prerequisites)
2. [New repository](#new-repository)
3. [Existing repository](#existing-repository)
4. [Day-to-day workflow](#day-to-day-workflow)
5. [Configuration reference](#configuration-reference)
6. [Monorepos](#monorepos)
7. [FOSS compliance](#foss-compliance)
8. [Staying up to date](#staying-up-to-date)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Install Nix via the [Determinate Systems installer](https://determinate.systems/nix/) (enables flakes by default):

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Or use the [official installer](https://nixos.org/download/) and add to `~/.config/nix/nix.conf`:

```ini
experimental-features = nix-command flakes
```

A **flake** is a `flake.nix` declaring inputs (dependencies) and outputs (packages, dev shells, checks, workflow files). All inputs are pinned in `flake.lock`. The engineering-standards module adds the `famedly.standards.*` and `famedly.github.workflows.*` option namespaces.

---

## New repository

```sh
nix flake init -t github:famedly/engineering-standards#dart   # or #rust, #flutter, #flutter-rust
nix flake update
nix run .#regenerateStandards
nix flake check
```

Commit everything including `flake.lock` and `.engineering-standards-manifest`.

---

## Existing repository

### 1. Add input

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  flake-parts.url = "github:hercules-ci/flake-parts";
  engineering-standards.url = "github:famedly/engineering-standards";
};

outputs = { flake-parts, ... }@inputs:
  flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.engineering-standards.flakeModules.default ];
  };
```

### 2. Configure

```nix
perSystem = { config, pkgs, lib, ... }: {
  famedly.standards = {
    linting = { enable = true; dart = true; };
    preCommitHooks = { enable = true; dartHooks.enable = true; };
    infrastructure = { editorconfig = true; dependabot = true; dependabotDart = true; };
    devShell.enable = true;
    dart.enable = true;
  };

  famedly.github.workflows = {
    ci.enable = true;
    "general-checks".enable = true;
  };

  devShells.default = pkgs.mkShell {
    inputsFrom = lib.optionals
      (config.famedly.standards.devShell.enable && config.devShells ? famedly-standards)
      [ config.devShells.famedly-standards ];
    packages = [ pkgs.dart ];
  };
};
```

### 3. Finalize

```sh
nix flake lock && nix run .#regenerateStandards && nix flake check
git add -A && git commit -m "feat: adopt engineering-standards"
```

Remove legacy CI workflows (`famedly/*-workflows`, `general.yml`, sync workflows).

---

## Day-to-day workflow

### Dev shell

```sh
nix develop
```

Pre-commit hooks are installed automatically on first entry. Wire into your own shell with `inputsFrom`:

```nix
devShells.default = pkgs.mkShell {
  inputsFrom = lib.optionals
    (config.famedly.standards.devShell.enable && config.devShells ? famedly-standards)
    [ config.devShells.famedly-standards ];
};
```

### CLI commands

| Command | What it does |
|---------|-------------|
| `famedly-regen` | Regenerate managed files (pinned input) |
| `famedly-regen --dev` | Regenerate with local `../engineering-standards` (override via `ENGINEERING_STANDARDS_PATH`) |
| `famedly-check` | `nix flake check -L` |
| `famedly-lint` | `pre-commit run --all-files` |
| `famedly-lint --fix` | Same, continue on errors |
| `famedly-update` | Update input + regenerate + check |
| `famedly-help` | List commands |

### Pre-commit hooks

| Group | Enabled when | Hooks |
|-------|-------------|-------|
| Base | `preCommitHooks.enable` | byte-order-marker, case-conflicts, merge-conflicts, symlinks, yaml, toml, json, eof-fixer, mixed-line-endings, trailing-whitespace, typos |
| FOSS | `fossHooks.enable` (default) | reuse |
| Rust | `rustHooks.enable` | clippy, rustfmt |
| Dart | `dartHooks.enable` | dart format, dart analyze `--fatal-infos` |
| Python | `pythonHooks.enable` | ruff check, ruff format |

### Managed files

`famedly-regen` writes all managed files and updates `.engineering-standards-manifest`. Do not hand-edit managed files — change Nix options instead.

---

## Configuration reference

### `famedly.standards.*`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rules.enable` | bool | `false` | Generate `.cursor/rules/standards/`, `CLAUDE.md` |
| `rules.extraScopes` | listOf enum | `[]` | `"dart"`, `"flutter"`, `"rust"`, `"python"`, `"typescript"` |
| `linting.enable` | bool | `false` | Master switch for lint configs |
| `linting.dart` | bool | `false` | `analysis_options.yaml` (Dart) |
| `linting.flutter` | bool | `false` | `analysis_options.yaml` (Flutter) |
| `linting.rust` | bool | `false` | `deny.toml`, `rustfmt.toml` |
| `linting.python` | bool | `false` | `pyproject.toml` (ruff) |
| `linting.typescript` | bool | `false` | TypeScript lint config |
| `preCommitHooks.enable` | bool | `false` | git-hooks.nix suite |
| `preCommitHooks.fossHooks.enable` | bool | `true` | REUSE compliance hook |
| `preCommitHooks.fossHooks.copyright` | str | `"Famedly GmbH"` | SPDX copyright holder |
| `preCommitHooks.fossHooks.license` | str | `"AGPL-3.0-only"` | SPDX license identifier |
| `preCommitHooks.rustHooks.enable` | bool | `false` | clippy + rustfmt |
| `preCommitHooks.dartHooks.enable` | bool | `false` | dart format + dart analyze |
| `preCommitHooks.pythonHooks.enable` | bool | `false` | ruff check + ruff format |
| `infrastructure.editorconfig` | bool | `true` | `.editorconfig` |
| `infrastructure.dependabot` | bool | `true` | `.github/dependabot.yml` |
| `infrastructure.dependabotDart` | bool | `false` | pub ecosystem |
| `infrastructure.dependabotRust` | bool | `false` | cargo ecosystem |
| `infrastructure.dependabotPython` | bool | `false` | pip ecosystem |
| `infrastructure.dependabotDocker` | bool | `false` | Docker ecosystem |
| `infrastructure.dependabotNpm` | bool | `false` | npm ecosystem |
| `infrastructure.dependabotTerraform` | bool | `false` | terraform ecosystem |
| `devShell.enable` | bool | `false` | `devShells.famedly-standards` + CLI commands |
| `devShell.extraPackages` | listOf package | `[]` | Additional packages |
| `dart.enable` | bool | `false` | Dart/Flutter dev shell, auto-enables `dart-ci` |
| `dart.flutter` | bool | `false` | Flutter SDK statt Dart SDK |
| `dart.dartSdk` | nullOr package | `null` | Override SDK package |

### `famedly.github.workflows.*`

All workflows have `enable` (bool, default `false`).

| Workflow | Key options |
|----------|-----------|
| `ci` | `armRunners` |
| `general-checks` | — |
| `authenticate-commits` | — |
| `fast-forward` | — |
| `add-to-project` | `projectUrl` |
| `update-openpgp-policy` | `teams` |
| `ai-review` | `model` |
| `release` | `draft` |
| `rust-ci` | `runner`, `container`, `features`, `packages`, `additionalPackages`, `coverage`, `typos`, `cargoDeny` |
| `dart-ci` | `packages` (attrsOf: `directory`, `sdk`, `test`, `coverage`, `coverageFlags`) |
| `publish-crate` | `packages`, `features`, `extraTagPatterns` |
| `publish-pub` | — |
| `docker` | `mode` (`multi-arch`/`simple`), `imageName`, `registry`, `triggerMode` (`direct`/`workflowRun`), `triggerWorkflow`, `buildArgs`, `pushOnlyOnTags`, `registryUser`, `registryPasswordSecret`, `context`, `dockerfile` |
| `docker-backend` | `targets`, `oss` |
| `docker-bake` | `files`, `targets` |
| `github-pages` | `artifactName`, `triggerWorkflows`, `triggerBranches` |
| `review-app` | `projectName`, `environment`, `triggerMode` (`direct`/`workflowRun`), `triggerWorkflow`, `artifactName` |
| `hookd-deploy` | `hookdUrl`, `hookdEndpoint`, `triggerWorkflow`, `secretName`, `environment`, `tagPrefix` |
| `ansible-ci` | `collection` |
| `update-engineering-standards` | `schedule` |

### Multi-package Dart CI

`dart-ci.packages` is an `attrsOf submodule`. Each entry produces independent lint/test/coverage jobs:

```nix
dart-ci = {
  enable = true;
  packages = {
    sdk = { sdk = "dart"; coverage = true; coverageFlags = "sdk-tests"; };
    testdriver = { directory = "ti_testdriver"; sdk = "dart"; coverage = false; };
    app = { directory = "example/app"; sdk = "flutter"; };
  };
};
```

Per-package options: `directory` (str, `""`), `sdk` (enum, `"flutter"`), `test` (bool, `true`), `coverage` (bool, `true`), `coverageFlags` (str, `""`).

### `workflow_run` triggers

`docker`, `review-app`, `github-pages`, and `hookd-deploy` support triggering after another workflow completes via `workflow_run`. Set `triggerMode = "workflowRun"` and `triggerWorkflow = "Upstream Workflow Name"`. This replaces `workflow_call` reusable workflows — each generated workflow is fully self-contained.

```nix
docker = {
  enable = true;
  mode = "simple";
  triggerMode = "workflowRun";
  triggerWorkflow = "My CI";
  imageName = "my-image";
  pushOnlyOnTags = true;
};

review-app = {
  enable = true;
  triggerMode = "workflowRun";
  triggerWorkflow = "My CI";
  projectName = "my-project";
};

hookd-deploy = {
  enable = true;
  triggerWorkflow = "Docker — Build & Push";
  hookdUrl = "https://my-webhook.famedly.de";
};
```

---

## Monorepos

`famedly.standards.projects` — per-directory lint configs, Dependabot entries, scoped pre-commit hooks:

```nix
famedly.standards.projects = {
  backend = { language = "rust"; directory = "backend"; };
  frontend = { language = "flutter"; directory = "frontend"; };
};

famedly.github.workflows.dart-ci.packages.frontend = {
  directory = "frontend";
  sdk = "flutter";
};
```

Per-project options: `language` (required: `"rust"`, `"dart"`, `"flutter"`, `"python"`, `"typescript"`), `directory` (str), `linting` (bool, `true`), `dependabot` (bool, `true`), `hooks` (bool, `true`).

Do not enable the same language at root level and in `projects` — that duplicates configs.

---

## FOSS compliance

When `fossHooks.enable = true` (default): `reuse` hook checks SPDX headers, `REUSE.toml` is generated for managed files, `addLicenseHeaders` app is available.

```sh
nix run .#addLicenseHeaders    # annotate files
reuse lint                     # verify
```

Configure copyright/license:

```nix
preCommitHooks.fossHooks = { copyright = "Your Company"; license = "Apache-2.0"; };
```

---

## Staying up to date

### Automated

```nix
famedly.github.workflows."update-engineering-standards".enable = true;
```

Runs on schedule (default: Mondays 06:00 UTC), bumps input, regenerates, opens PR.

### Manual

```sh
famedly-update    # or step by step:
# nix flake update engineering-standards && nix run .#regenerateStandards && nix flake check
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `experimental Nix feature 'flakes' is disabled` | Enable flakes in `nix.conf` |
| `nix flake check` differs locally vs CI | Run `nix flake update`, commit `flake.lock` |
| Pre-commit hooks missing after `nix develop` | `exit && nix develop` or `pre-commit install` |
| `dart analyze` fails on info-level hints | Hook uses `--fatal-infos`; fix all hints |
| `reuse lint` fails | `nix run .#addLicenseHeaders` |
| Managed file overwritten | Don't hand-edit; change Nix options, re-run `famedly-regen` |
| `nix flake lock` input resolution error | Check URL `github:famedly/engineering-standards`, check network |
| Wrong workflow content after option change | `famedly-regen` + commit |
