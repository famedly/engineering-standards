# Adopting engineering-standards

This guide walks you through adopting the engineering-standards Nix module in a Famedly repository — from first-time Nix setup through day-to-day development.

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

### Install Nix

Install Nix using the [Determinate Systems installer](https://determinate.systems/nix/) (recommended — enables flakes by default):

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Alternatively, use the [official installer](https://nixos.org/download/) and then enable flakes manually by adding this to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`:

```ini
experimental-features = nix-command flakes
```

### What is a Nix flake?

A **flake** is a `flake.nix` file at the root of your repository. It declares:

- **inputs** — other flakes your project depends on (e.g. nixpkgs, engineering-standards)
- **outputs** — everything your project provides: packages, dev shells, CI checks, GitHub workflow files

All inputs are pinned in `flake.lock`, making builds fully reproducible. The engineering-standards module is one such input; importing it adds the `famedly.standards.*` and `famedly.github.workflows.*` option namespaces to your flake.

---

## New repository

For an empty directory (or after `git init`), use one of the provided templates:

```sh
# Pick the template matching your stack:
nix flake init -t github:famedly/engineering-standards#rust
nix flake init -t github:famedly/engineering-standards#dart
nix flake init -t github:famedly/engineering-standards#flutter
nix flake init -t github:famedly/engineering-standards#flutter-rust   # monorepo

nix flake update                   # create flake.lock with pinned inputs
nix run .#regenerateStandards      # write managed files (.editorconfig, workflows, lint configs, …)
nix flake check                    # verify everything evaluates and checks pass
```

What each command does:

| Command | What happens |
|---------|-------------|
| `nix flake init -t …` | Copies a `flake.nix` template into your directory |
| `nix flake update` | Resolves all inputs and writes `flake.lock` |
| `nix run .#regenerateStandards` | Generates all files declared as managed (workflows, `.editorconfig`, lint configs, …) and writes `.engineering-standards-manifest` |
| `nix flake check` | Evaluates all checks in the flake — including the pre-commit hook suite if enabled |

After these steps, commit everything including `flake.lock` and `.engineering-standards-manifest`.

---

## Existing repository

### 1. Add the input and import the module

```nix
# flake.nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  flake-parts.url = "github:hercules-ci/flake-parts";
  engineering-standards.url = "github:famedly/engineering-standards";
};

outputs =
  { flake-parts, ... }@inputs:
  flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.engineering-standards.flakeModules.default ];
    # …
  };
```

### 2. Configure standards and workflows

Under `perSystem`, set the options for your stack. Example for a Dart project:

```nix
perSystem =
  { config, pkgs, lib, ... }:
  {
    famedly.standards = {
      linting = {
        enable = true;
        dart = true;
      };
      preCommitHooks = {
        enable = true;
        dartHooks.enable = true;
      };
      infrastructure = {
        editorconfig = true;
        dependabot = true;
        dependabotDart = true;
      };
      devShell.enable = true;
      dart.enable = true;
    };

    famedly.github.workflows = {
      ci.enable = true;
      "general-checks".enable = true;
      # dart-ci is auto-enabled by dart.enable = true
    };

    devShells.default = pkgs.mkShell {
      inputsFrom = lib.optionals (
        config.famedly.standards.devShell.enable && config.devShells ? famedly-standards
      ) [ config.devShells.famedly-standards ];
      packages = [ pkgs.dart ];
    };
  };
```

### 3. Finalize

```sh
nix flake lock                   # pin the new input
nix run .#regenerateStandards    # generate managed files
nix flake check                  # verify
git add -A && git commit -m "feat: adopt engineering-standards"
```

Remove any old duplicated CI workflows (legacy `famedly/*-workflows` references, `general.yml`, sync workflows) so you are not running two systems in parallel.

---

## Day-to-day workflow

### Entering the dev shell

```sh
nix develop
```

When you enter the dev shell for the first time (or after `nix flake update`), the shell hook from `git-hooks.nix` automatically installs pre-commit hooks into `.git/hooks/pre-commit`. You get all hook tools (typos, reuse, clippy, dart, ruff, …) on your `PATH` without any separate installation step.

To wire the `famedly-standards` shell into your own `devShells.default`, use `inputsFrom`:

```nix
devShells.default = pkgs.mkShell {
  inputsFrom = lib.optionals (
    config.famedly.standards.devShell.enable && config.devShells ? famedly-standards
  ) [ config.devShells.famedly-standards ];
  packages = [ /* your additional packages */ ];
};
```

### Pre-commit hooks

Hooks run automatically on `git commit`. You can also run them manually inside the dev shell:

```sh
pre-commit run --all-files
```

The following hook groups are available:

| Group | Enabled when | Hooks |
|-------|-------------|-------|
| Base | always (when `preCommitHooks.enable = true`) | `fix-byte-order-marker`, `check-case-conflicts`, `check-merge-conflicts`, `check-symlinks`, `check-yaml`, `check-toml`, `check-json`, `end-of-file-fixer`, `mixed-line-endings`, `trim-trailing-whitespace`, `typos` |
| FOSS | `fossHooks.enable = true` (default) | `reuse` (SPDX license compliance) |
| Rust | `rustHooks.enable = true` | `clippy` (deny warnings, all targets), `rustfmt` (nightly, check mode) |
| Dart | `dartHooks.enable = true` | `dart format`, `dart analyze --fatal-infos` |
| Python | `pythonHooks.enable = true` | `ruff check --fix`, `ruff format` |

> **Note on `--fatal-infos`:** The Dart analyzer hook runs with `--fatal-infos`, meaning info-level diagnostics (not just warnings/errors) will cause the hook to fail. Fix all reported hints before committing.

### Regenerating managed files

```sh
nix run .#regenerateStandards
```

This command writes all files that the module manages (`.editorconfig`, `.github/workflows/*.yml`, lint config files, Cursor rules, …) and removes any previously generated files that belong to features you have since disabled. It maintains `.engineering-standards-manifest` to track which files it owns — commit this file together with the generated output.

**Do not hand-edit managed files.** Change the Nix options and re-run `regenerateStandards` instead.

### Running checks locally

```sh
nix flake check
```

This runs all checks defined in your flake, including the pre-commit hook suite (exposed as a check derivation by `git-hooks.nix`). This is identical to what CI runs with `nix flake check -L`. If it passes locally, it will pass in CI.

---

## Configuration reference

### `famedly.standards.*`

#### `rules`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rules.enable` | `bool` | `false` | Generate AI assistant rule files (`.cursor/rules/standards/`, `CLAUDE.md`) |
| `rules.extraScopes` | `listOf enum` | `[]` | Additional language scopes: `"dart"`, `"flutter"`, `"rust"`, `"python"`, `"typescript"` |

#### `linting`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `linting.enable` | `bool` | `false` | Master switch; must be `true` for any language config to be generated |
| `linting.dart` | `bool` | `false` | Generate `analysis_options.yaml` for Dart |
| `linting.flutter` | `bool` | `false` | Generate `analysis_options.yaml` for Flutter |
| `linting.rust` | `bool` | `false` | Generate `deny.toml` and `rustfmt.toml` |
| `linting.python` | `bool` | `false` | Generate `pyproject.toml` (ruff config) |
| `linting.typescript` | `bool` | `false` | Generate TypeScript lint config |

> `analysis_options.yaml` (Dart/Flutter) is written with `initialOnly = true` — it is only created if it does not already exist, so you can extend it freely.

#### `preCommitHooks`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `preCommitHooks.enable` | `bool` | `false` | Enable git-hooks.nix pre-commit suite |
| `preCommitHooks.fossHooks.enable` | `bool` | `true` | Enable REUSE license compliance hook |
| `preCommitHooks.fossHooks.copyright` | `str` | `"Famedly GmbH"` | Copyright holder for SPDX headers |
| `preCommitHooks.fossHooks.license` | `str` | `"AGPL-3.0-only"` | SPDX license identifier for headers |
| `preCommitHooks.rustHooks.enable` | `bool` | `false` | Enable clippy and rustfmt hooks |
| `preCommitHooks.dartHooks.enable` | `bool` | `false` | Enable dart format and dart analyze hooks |
| `preCommitHooks.pythonHooks.enable` | `bool` | `false` | Enable ruff check and ruff format hooks |

#### `infrastructure`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `infrastructure.editorconfig` | `bool` | `true` | Generate `.editorconfig` |
| `infrastructure.dependabot` | `bool` | `true` | Generate `.github/dependabot.yml` (Nix ecosystem) |
| `infrastructure.dependabotDart` | `bool` | `false` | Add pub ecosystem entry to Dependabot |
| `infrastructure.dependabotRust` | `bool` | `false` | Add cargo ecosystem entry |
| `infrastructure.dependabotPython` | `bool` | `false` | Add pip ecosystem entry |
| `infrastructure.dependabotDocker` | `bool` | `false` | Add Docker ecosystem entry |
| `infrastructure.dependabotNpm` | `bool` | `false` | Add npm ecosystem entry |
| `infrastructure.dependabotTerraform` | `bool` | `false` | Add terraform ecosystem entry |

#### `devShell`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `devShell.enable` | `bool` | `false` | Create `devShells.famedly-standards` with hook tools and shell hook |
| `devShell.extraPackages` | `listOf package` | `[]` | Additional packages to include in the dev shell |

#### `dart`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dart.enable` | `bool` | `false` | Enable Dart/Flutter dev shell and auto-enable `dart-ci` workflow |
| `dart.flutter` | `bool` | `false` | Use Flutter SDK instead of plain Dart SDK |
| `dart.dartSdk` | `nullOr package` | `null` | Override the Dart/Flutter package (defaults to nixpkgs `dart` or `flutter`) |

#### `projects` (monorepo)

See the [Monorepos](#monorepos) section.

---

### `famedly.github.workflows.*`

Enable each workflow individually. All share an `enable` option (default `false`).

| Workflow | Extra options | Notes |
|----------|--------------|-------|
| `ci` | `armRunners` (bool, default `false`) | Runs `nix flake check -L` in CI |
| `general-checks` | — | Branch naming, PR title, commit hygiene |
| `authenticate-commits` | — | OpenPGP/SSH commit signature verification |
| `fast-forward` | — | `/fast-forward` comment triggers PR merge |
| `add-to-project` | `projectUrl` (str) | Add issues/PRs to a GitHub Project |
| `update-openpgp-policy` | `teams` (str) | Update OpenPGP key policy for teams |
| `ai-review` | `model` (str, default `"claude-sonnet-4-5"`) | AI-assisted PR review |
| `release` | `draft` (bool, default `false`) | GitHub release via gh CLI |
| `rust-ci` | `runner`, `container`, `features`, `packages`, `additionalPackages`, `coverage` (bool, default `true`), `typos` (bool, default `true`), `cargoDeny` (bool, default `false`) | Full Rust CI: tests, coverage, typos, cargo-deny |
| `dart-ci` | `directory` (str, default `""`), `sdk` (enum `"flutter"`/`"dart"`, default `"flutter"`) | Dart/Flutter CI; auto-enabled by `dart.enable = true` |
| `publish-crate` | `packages`, `features`, `extraTagPatterns` (listOf str) | Publish crates to crates.io |
| `publish-pub` | — | Publish packages to pub.dev |
| `docker` | `imageName`, `registry` (default `"ghcr.io"`), `armRunner`, `amd64Runner` | Build and push Docker image |
| `docker-backend` | `targets` (str), `oss` (bool, default `false`) | Multi-target Docker backend builds |
| `docker-bake` | `files` (default `"docker-bake.hcl"`), `targets` (default `"default"`) | Docker Bake builds |
| `github-pages` | `artifactName` (str, default `"github-pages"`) | Deploy to GitHub Pages |
| `review-app` | `projectName` (str), `environment` (str, default `"review"`) | Deploy review apps |
| `ansible-ci` | `collection` (str) | Ansible collection CI |
| `update-engineering-standards` | `schedule` (str, cron) | Scheduled PR to bump this input and regenerate |

All workflow YAML is generated directly from Nix — there are no `workflow_call` indirections. Tools like typos, cargo-deny, dart, and flutter are installed at CI time via `nix profile install`, pinned to the flake's `nixpkgs` revision.

---

## Monorepos

Use `famedly.standards.projects` when a single repository contains multiple language roots (e.g. a Flutter frontend and a Rust backend). Each project entry generates scoped lint configs, Dependabot entries, and directory-scoped pre-commit hooks.

```nix
famedly.standards = {
  preCommitHooks.enable = true;
  infrastructure = {
    editorconfig = true;
    dependabot = true;
  };
  devShell.enable = true;

  projects = {
    backend = {
      language = "rust";
      directory = "backend";
    };
    frontend = {
      language = "flutter";
      directory = "frontend";
    };
  };

  dart = {
    enable = true;
    flutter = true;
  };
};

famedly.github.workflows = {
  ci.enable = true;
  "general-checks".enable = true;
  "dart-ci".directory = "frontend";   # point dart-ci at the Flutter subdirectory
};
```

Per-project options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `language` | enum | (required) | `"rust"`, `"dart"`, `"flutter"`, `"python"`, `"typescript"` |
| `directory` | str | `""` | Path relative to repo root (e.g. `"backend"`) |
| `linting` | bool | `true` | Generate lint config for this project |
| `dependabot` | bool | `true` | Add Dependabot entry for this project |
| `hooks` | bool | `true` | Include scoped pre-commit hooks for this project |

> Do not also enable the same language at the root level (e.g. `linting.rust = true`) when you have a `projects` entry for it — that would duplicate configs.

Expected directory layout for the `flutter-rust` template:

```
├── flake.nix
├── frontend/          # Flutter app
│   ├── pubspec.yaml
│   └── lib/
└── backend/           # Rust service
    ├── Cargo.toml
    └── src/
```

---

## FOSS compliance

When `preCommitHooks.fossHooks.enable = true` (the default when `preCommitHooks.enable = true`), the module:

- Enables the `reuse` pre-commit hook, which checks that all files have SPDX license headers and that license texts are present in `LICENSES/`
- Generates an initial `REUSE.toml` covering standard managed files (`.editorconfig`, `.github/`, `.cursor/rules/standards/`, etc.)
- Provides the `addLicenseHeaders` app

### Adding license headers

If the `reuse` hook fails because files are missing SPDX headers, run:

```sh
nix run .#addLicenseHeaders
```

This annotates all git-tracked files with the configured copyright and license identifier and downloads any missing license texts. Configure the defaults in your flake:

```nix
preCommitHooks = {
  enable = true;
  fossHooks = {
    enable = true;
    copyright = "Your Company Name";
    license = "Apache-2.0";
  };
};
```

After running `addLicenseHeaders`, verify with:

```sh
reuse lint
```

---

## Staying up to date

### Automated updates

Enable the update workflow in your flake:

```nix
famedly.github.workflows."update-engineering-standards".enable = true;
```

After regenerating (`nix run .#regenerateStandards`), a workflow appears at `.github/workflows/update-engineering-standards.yml`. It runs on a schedule (default: Mondays at 06:00 UTC), bumps the `engineering-standards` input in `flake.lock`, re-runs `regenerateStandards`, and opens a PR with the diff.

You can also trigger it manually from the GitHub Actions UI or via `repository_dispatch`.

### Manual update

```sh
nix flake update engineering-standards    # or: nix flake update (updates all inputs)
nix run .#regenerateStandards
nix flake check
git add flake.lock .engineering-standards-manifest
git add -u                                # stage any changed managed files
git commit -m "chore: update engineering-standards"
```

---

## Troubleshooting

**`error: experimental Nix feature 'flakes' is disabled`**
Enable flakes in your `nix.conf` (see [Prerequisites](#prerequisites)).

**`nix flake check` fails locally but CI is green (or vice versa)**
CI runs `nix flake check -L` on the exact same flake inputs pinned in `flake.lock`. If they differ, run `nix flake update` and re-check locally. Make sure you have committed `flake.lock`.

**Pre-commit hooks not installed after `nix develop`**
The shell hook installs hooks automatically on first entry. If hooks are missing, exit and re-enter the shell: `exit && nix develop`. Alternatively run `pre-commit install` manually inside the dev shell.

**`dart analyze` fails with info-level hints**
The hook runs with `--fatal-infos`. Fix all reported hints (even info-level ones) or suppress them with `// ignore: <rule>` annotations in the source.

**`reuse lint` fails after adding new files**
Run `nix run .#addLicenseHeaders` to annotate new files, then commit the changes.

**Managed file was hand-edited and `regenerateStandards` overwrites it**
Only edit managed files through Nix options. Check `.engineering-standards-manifest` to see which files are managed. If you need to diverge from the generated content, disable the relevant option and maintain the file manually.

**`nix flake lock` fails with input resolution errors**
Ensure the `engineering-standards` URL is correct (`github:famedly/engineering-standards`) and that your network can reach GitHub. For private registries or offline setups, contact the maintainers.

**CI workflow generated with wrong content after option change**
Run `nix run .#regenerateStandards` and commit the updated workflow file. The `ci` check in `nix flake check` enforces that generated files match the current Nix configuration.
