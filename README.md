# engineering-standards

Engineering rules and tooling for the org. Includes automated dependency updates (Dependabot), GitHub Actions SHA pinning (pinact), AI code review (Claude), and editor rule syncing.

Root-level rules in `.github/rules/` apply to all repos. Language-specific rules in `dart/`, `rust/`, and `python/` are loaded based on what the repo contains.

## What's included

| Feature | Type | Description |
|---|---|---|
| **Dependabot** | Base (required) | Automated dependency updates via GitHub-native Dependabot |
| **pinact** | Policy (org-level) | GitHub Actions references pinned to full-length commit SHAs |
| **Claude Linter** | Optional | AI code review on PRs via `@check-standards` |
| **Editor Sync** | Optional | Syncs rules to `.cursor/rules/` and `CLAUDE.md` |

## Dependabot (dependency updates)

Each repository gets a `.github/dependabot.yml` generated from the central template based on detected ecosystems. The template is defined in `scripts/generate-dependabot.sh`.

### Supported ecosystems

| Ecosystem | Detected by | Package ecosystem |
|---|---|---|
| GitHub Actions | always included | `github-actions` |
| Dart/Flutter | `pubspec.yaml` | `pub` |
| Rust | `Cargo.toml` | `cargo` |
| Python | `requirements.txt`, `pyproject.toml`, `setup.py`, `Pipfile` | `pip` |
| Docker | `Dockerfile`, `docker-compose.yml` | `docker` |

### Configuration highlights

- **Schedule**: daily, Europe/Berlin timezone
- **Grouping**: major updates separate from minor+patch (fewer PRs, clear risk separation)
- **Cooldown**: 3 days for minor/patch, 7 days for major (avoids broken releases)
- **Commit messages**: `chore(deps): ` prefix with scope
- **PR limit**: 10 per ecosystem
- **Private registries**: `DEPENDABOT_SECRET` (PAT with repo scope) for private GitHub packages
- **Commits**: automatically signed by GitHub (no GPG setup needed)

### Drift prevention

The `sync-standards.yml` workflow regenerates `.github/dependabot.yml` weekly from the central template. If a repo's config drifts, the sync opens a PR to bring it back in line.

### Example generated config (Dart repo)

```yaml
version: 2
registries:
  private-github:
    type: git
    url: https://github.com
    username: x-access-token
    password: ${{secrets.DEPENDABOT_SECRET}}
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "daily"
      timezone: "Europe/Berlin"
    groups:
      actions:
        patterns: ["*"]
    commit-message:
      prefix: "chore(deps): "

  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "daily"
      timezone: "Europe/Berlin"
    open-pull-requests-limit: 10
    registries:
      - private-github
    groups:
      major:
        update-types: ["major"]
      minor-and-patch:
        update-types: ["minor", "patch"]
    commit-message:
      prefix: "chore(deps): "
      include: "scope"
    cooldown:
      default-days: 3
      semver-major-days: 7
```

## GitHub Actions SHA pinning (pinact)

All GitHub Actions references must use full-length commit SHAs instead of tags. This is enforced by a GitHub organization policy:

> **Settings → Code security → Actions → Require actions to be pinned to a full-length commit SHA**

Use [pinact](https://github.com/suzuki-shunsuke/pinact) to convert tag-based references:

```bash
# Install
go install github.com/suzuki-shunsuke/pinact/v3/cmd/pinact@latest

# Convert all workflows
pinact run
```

Dependabot's `github-actions` ecosystem automatically updates the SHA pins when new versions are released.

## CI (AI code review)

Other repos call `claude-linter.yml` as a reusable workflow:

```yaml
# .github/workflows/lint.yml
jobs:
  lint:
    uses: famedly/engineering-standards/.github/workflows/claude-linter.yml@main
    with:
      rule_scope: "dart"   # or "rust", "python", or "dart rust"
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      ENGINEERING_STANDARDS_READ: ${{ secrets.ENGINEERING_STANDARDS_READ }}
```

Without `rule_scope`, only the general rules apply.

## Editor sync

Drop `sync-standards.yml` into a repo's `.github/workflows/`. It runs weekly (Monday 06:00 UTC) and on manual trigger. It:

- Detects the language from `pubspec.yaml` / `Cargo.toml` / `requirements.txt` etc.
- Copies the matching rules to `.cursor/rules/standards/` (Cursor) and `CLAUDE.md` (Claude CLI)
- Regenerates `.github/dependabot.yml` from the central template (drift prevention)
- Opens a PR if anything changed

## Rollout

To deploy to all existing repos:

```bash
# Dependabot only (base/required)
./scripts/rollout-sync-workflow.sh famedly --dry-run
./scripts/rollout-sync-workflow.sh famedly

# Dependabot + AI workflows
./scripts/rollout-sync-workflow.sh famedly --with-ai --dry-run
./scripts/rollout-sync-workflow.sh famedly --with-ai
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

1. Store `DEPENDABOT_SECRET` as an org-level GitHub secret (PAT with `repo` scope for private package access)
2. Enable the org policy: **Settings → Code security → Actions → Require actions to be pinned to a full-length commit SHA**
3. Store `ANTHROPIC_API_KEY` as an org-level GitHub secret (for AI features)
4. Create a PAT with `repo` scope (read access to `engineering-standards`) and store it as org secret `ENGINEERING_STANDARDS_READ`
5. Run the [rollout script](#rollout) to deploy to all repos
6. Run `pinact run` in each repo to convert existing tag-based Action references to SHAs

---

Supersedes:
- https://www.notion.so/famedly/Code-Quality-Standards-1344c3a979208088aa51ef00fbb0e8eb
- https://www.notion.so/famedly/Technical-Writing-Style-Guide-29d4c3a97920800b9284eaa64c80a269
- https://www.notion.so/famedly/DRAFT-Code-Documentation-Standards-1304c3a9792080fc8245cbd2616a9524
- https://www.notion.so/famedly/Logging-Policy-12d4c3a9792080b686a8cf83bfde3ec3
