# engineering-standards

Engineering rules for the org. Enforced via Claude in CI, synced to Cursor and Claude CLI locally.

Root-level rules in `.github/rules/` apply to all repos. Language-specific rules in `dart/` and `rust/` are loaded based on what the repo contains.

## CI

Other repos call `claude-linter.yml` as a reusable workflow:

```yaml
# .github/workflows/lint.yml
jobs:
  lint:
    uses: famedly/engineering-standards/.github/workflows/claude-linter.yml@main
    with:
      rule_scope: "dart"   # or "rust", or "dart rust"
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      ENGINEERING_STANDARDS_READ: ${{ secrets.ENGINEERING_STANDARDS_READ }}
```

Without `rule_scope`, only the general rules apply.

## Editor sync

Drop `sync-standards.yml` into a repo's `.github/workflows/`. It runs weekly (Monday 06:00 UTC) and on manual trigger. It:

- Detects the language from `pubspec.yaml` / `Cargo.toml`
- Copies the matching rules to `.cursor/rules/standards/` (Cursor) and `CLAUDE.md` (Claude CLI)
- Opens a PR if anything changed

## Rollout

To add the sync workflow to all existing repos at once:

```bash
./scripts/rollout-sync-workflow.sh famedly --dry-run   # preview
./scripts/rollout-sync-workflow.sh famedly              # create PRs
```

Requires `gh` CLI with a PAT that has `repo` and `workflow` scopes.

## Adding rules

Add a `.md` file to `.github/rules/` or a language subdirectory. Both CI and editor sync pick it up automatically.

## Releases

Changes are tracked in [CHANGELOG.md](CHANGELOG.md). To cut a release:

1. Update `CHANGELOG.md` with the new version and changes
2. Merge to `main`
3. Tag: `git tag v1.x.0 && git push origin v1.x.0`

A GitHub Release with the changelog extract is created automatically.

## Setup

1. Store `ANTHROPIC_API_KEY` as an org-level GitHub secret
2. Create a PAT with `repo` scope (read access to `engineering-standards`) and store it as org secret `ENGINEERING_STANDARDS_READ`
3. Add `claude-linter.yml` to repos that need CI review
4. Add `sync-standards.yml` to repos that need editor rules (or use the [rollout script](#rollout))

---

Supersedes:
- https://www.notion.so/famedly/Code-Quality-Standards-1344c3a979208088aa51ef00fbb0e8eb
- https://www.notion.so/famedly/Technical-Writing-Style-Guide-29d4c3a97920800b9284eaa64c80a269
- https://www.notion.so/famedly/DRAFT-Code-Documentation-Standards-1304c3a9792080fc8245cbd2616a9524
- https://www.notion.so/famedly/Logging-Policy-12d4c3a9792080b686a8cf83bfde3ec3
