---
name: add-github-workflow
description: Adds a new generated GitHub Actions workflow to the Famedly engineering-standards flake. Use when adding any `.github/workflows/*.yml` to consumer repos, when adding a new entry under `famedly.github.workflows.*`, or when the user asks to add or create a CI/CD workflow in this repository.
---

# Add a GitHub workflow

All workflow YAML in `engineering-standards` is **generated** from per-workflow Nix modules via [`synapdeck/github-actions-nix`](https://github.com/synapdeck/github-actions-nix). Never write `.github/workflows/*.yml` by hand and never use `workflow_call` reusable workflows.

## Where it lives

Create `nix/modules/workflows/definitions/<name>.nix`. The filename (without `.nix`) becomes the workflow option name and the generated YAML filename. The loader in `nix/modules/workflows/default.nix` auto-discovers everything in that directory via `builtins.readDir`, so no central registration is needed.

## Module shape

Each definition is a flake-parts module that receives `{ inputs, repoRoot, workflowsLib, famedlyConfig, config, lib, ... }`. The parent already provides `enable` and `extraManagedFiles` options; your file sets `config.definition` (and may add per-workflow options).

Reference the smallest existing example, [`nix/modules/workflows/definitions/general-checks.nix`](../../../nix/modules/workflows/definitions/general-checks.nix), as a template:

```nix
{ workflowsLib, famedlyConfig, ... }:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ciConcurrency;
in
{
  config.definition = {
    name = "My workflow";
    on.pullRequest = { };
    permissions.contents = "read";
    concurrency = ciConcurrency;
    jobs.my_job = {
      runsOn = "ubuntu-latest";
      steps = [
        { uses = "actions/checkout@${av.checkout}"; }
      ];
    };
  };
}
```

## Required conventions

- **SHA-pin every action.** Resolve via `famedlyConfig.standards.actionVersions.<name>` (defined in [`nix/action-versions-data.nix`](../../../nix/action-versions-data.nix) and exposed by [`nix/modules/action-versions.nix`](../../../nix/modules/action-versions.nix)). If the action you need is not in the list, add it there first.
- **No `workflow_call`.** If your workflow must run after another, use `triggerMode = "workflowRun"` with a `triggerWorkflow = "Upstream Name"` option. See [`definitions/docker.nix`](../../../nix/modules/workflows/definitions/docker.nix) and [`definitions/review-app.nix`](../../../nix/modules/workflows/definitions/review-app.nix) for the pattern.
- **Use `workflowsLib` helpers** (`ciConcurrency`, etc.) instead of duplicating boilerplate.

## Per-workflow options

If the workflow accepts user configuration, add an `options` block in the same file:

```nix
{ lib, config, ... }:
{
  options.myThing = lib.mkOption { type = lib.types.str; default = "x"; };
  config.definition = { /* uses config.myThing */ };
}
```

The parent `submoduleWith` merges this with the default `enable` / `definition` / `extraManagedFiles` options.

## Templates and docs

- If the new workflow should be enabled by default in any template, edit the matching `nix/templates/*/flake.nix`.
- Update user-facing documentation (workflow table in `docs/adopting.md`, `README.md` "What it provides" if relevant) by following [`../update-user-docs/SKILL.md`](../update-user-docs/SKILL.md).

## Verification

```sh
nix flake show                 # workflow appears under githubActions.workflows
nix flake check -L             # actionlint + dogfood checks must pass
```

Then enable it in a template (or this repo) and run `nix run .#regenerateStandards` to confirm the YAML emerges as expected.
