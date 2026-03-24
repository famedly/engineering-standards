# engineering-standards

Engineering rules and tooling for the org. Includes automated dependency updates (Renovate), AI code review (Claude), and editor rule syncing.

Root-level rules in `.github/rules/` apply to all repos. Language-specific rules in `dart/` and `rust/` are loaded based on what the repo contains.

## What's included

| Feature | Type | Description |
|---|---|---|
| **Renovate** | Base (required) | Automated dependency updates via centralized runner |
| **Claude Linter** | Optional | AI code review on PRs via `@check-standards` |
| **Editor Sync** | Optional | Syncs rules to `.cursor/rules/` and `CLAUDE.md` |

## Renovate (dependency updates)

A central Renovate runner (`renovate.yml`) scans all org repos with `autodiscover`. Each repo only needs a `renovate.json` that extends the shared presets:

```json
{
  "extends": [
    "github>famedly/engineering-standards//renovate/default",
    "github>famedly/engineering-standards//renovate/dart",
    "github>famedly/engineering-standards//renovate/private"
  ]
}
```

### Available presets

| Preset | Purpose |
|---|---|
| `renovate/default` | Base config: semantic commits, schedule, dashboard, PR limits |
| `renovate/dart` | Dart/Flutter: pub manager, range bumping, Flutter-managed deps disabled |
| `renovate/private` | Tracks private git dependencies with `ref:` via github-tags |

### How it works

- The central runner in this repo runs Mon–Fri at 04:00 UTC
- It autodiscovers all `famedly/*` repos that have a `renovate.json`
- PRs are created automatically for dependency updates
- Forks are excluded by default

### Secrets required

- `RENOVATE_TOKEN`: PAT with `repo` scope (org-level secret)

## CI (AI code review)

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
- Ensures `renovate.json` extends the correct presets (drift prevention)
- Opens a PR if anything changed

## Rollout

To deploy to all existing repos:

```bash
# Renovate only (base/required)
./scripts/rollout-sync-workflow.sh famedly --dry-run
./scripts/rollout-sync-workflow.sh famedly

# Renovate + AI workflows
./scripts/rollout-sync-workflow.sh famedly --with-ai --dry-run
./scripts/rollout-sync-workflow.sh famedly --with-ai

# Only renovate, skip AI even if --with-ai was used before
./scripts/rollout-sync-workflow.sh famedly --renovate-only
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

1. Store `RENOVATE_TOKEN` as an org-level GitHub secret (PAT with `repo` scope)
2. Store `ANTHROPIC_API_KEY` as an org-level GitHub secret (for AI features)
3. Create a PAT with `repo` scope (read access to `engineering-standards`) and store it as org secret `ENGINEERING_STANDARDS_READ`
4. Run the [rollout script](#rollout) to deploy to all repos

---

Supersedes:
- https://www.notion.so/famedly/Code-Quality-Standards-1344c3a979208088aa51ef00fbb0e8eb
- https://www.notion.so/famedly/Technical-Writing-Style-Guide-29d4c3a97920800b9284eaa64c80a269
- https://www.notion.so/famedly/DRAFT-Code-Documentation-Standards-1304c3a9792080fc8245cbd2616a9524
- https://www.notion.so/famedly/Logging-Policy-12d4c3a9792080b686a8cf83bfde3ec3
