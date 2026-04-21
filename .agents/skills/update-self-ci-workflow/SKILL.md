---
name: update-self-ci-workflow
description: Modifies the dogfooded CI workflow that the engineering-standards repo runs against itself. Use when changing `nix/modules/workflows/definitions/ci.nix`, when an agent notices a diff between `.github/workflows/ci.yml` and the Nix module output, or when the `ci-workflow-dogfood` check is failing.
---

# Update the dogfooded self-CI workflow

`engineering-standards` runs *its own* CI through the same Nix-generated workflow it ships to consumer repos. The generated `.github/workflows/ci.yml` is regenerated from [`nix/modules/workflows/definitions/ci.nix`](../../../nix/modules/workflows/definitions/ci.nix) and a `ci-workflow-dogfood` check in [`flake.nix`](../../../flake.nix) `diff`s the two and fails on drift. That drift check is intentional.

## Procedure

1. Edit only [`nix/modules/workflows/definitions/ci.nix`](../../../nix/modules/workflows/definitions/ci.nix). Never edit `.github/workflows/ci.yml` directly — its header explicitly forbids it.
2. Regenerate:

   ```sh
   nix run .#regenerateStandards
   ```

   This rewrites `.github/workflows/ci.yml` from the new module output and updates [`.engineering-standards-manifest`](../../../.engineering-standards-manifest) if managed-file paths changed.
3. Stage **both** the Nix change and the regenerated YAML in the same commit. Splitting them across commits will leave intermediate revisions failing `ci-workflow-dogfood`.

## What to keep in mind while editing `ci.nix`

- SHA-pin every action via `famedlyConfig.standards.actionVersions.<name>` (resolved from [`nix/action-versions-data.nix`](../../../nix/action-versions-data.nix)).
- Keep the entrypoint a single `nix flake check -L` invocation — that contract is what every consumer repo also runs.
- Cachix steps (`cachix/install-nix-action`, `cachix/cachix-action`) are required and use the `famedly` cache + the `CACHIX_*_FAMEDLY` secrets. Do not remove them.
- Use `workflowsLib.ciConcurrency` rather than hand-writing the concurrency block.

## Adding a new managed file alongside the workflow

If your change introduces an additional managed file (for example a composite action under `.github/actions/`):

- Push it onto `extraManagedFiles` for the `ci` workflow option (see how other definitions do this).
- Re-run `nix run .#regenerateStandards`. Verify the new file appears in `.engineering-standards-manifest` and any removed entries are cleaned up.

## Verification

```sh
nix flake check -L
```

The `ci-workflow-dogfood` derivation MUST pass. If it does not, the regenerated YAML on disk does not match the module output — re-run `nix run .#regenerateStandards` and re-stage the result.
