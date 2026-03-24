#!/usr/bin/env bash
set -euo pipefail

# Distributes engineering standards to all repositories in the GitHub
# organization. Renovate is always deployed (base/required). AI workflows
# (sync-standards, claude-linter) are opt-in via --with-ai.
#
# Prerequisites:
#   - gh CLI authenticated with an org-level PAT (repo + workflow scopes)
#   - The PAT must have write access to the target repositories
#
# Usage:
#   ./scripts/rollout-sync-workflow.sh <org> [--dry-run] [--with-ai] [--renovate-only]

ORG="${1:?Usage: $0 <org> [--dry-run] [--with-ai] [--renovate-only]}"
shift
DRY_RUN=""
WITH_AI=""
RENOVATE_ONLY=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="true" ;;
    --with-ai) WITH_AI="true" ;;
    --renovate-only) RENOVATE_ONLY="true" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC_SOURCE="$REPO_ROOT/.github/workflows/sync-standards.yml"
LINTER_TEMPLATE="$REPO_ROOT/.github/workflows/claude-linter.yml"
BRANCH="chore/add-engineering-standards"
SKIP_REPOS=("engineering-standards" ".github" "nehws")

detect_scope() {
  local dir="$1"
  local scope=""
  [ -f "$dir/pubspec.yaml" ] && scope="dart"
  [ -f "$dir/Cargo.toml" ] && scope="${scope:+$scope }rust"
  echo "$scope"
}

generate_renovate_json() {
  local scope="$1"
  local presets='"github>'"$ORG"'/engineering-standards//renovate/default"'

  for lang in $scope; do
    presets="$presets, \"github>$ORG/engineering-standards//renovate/$lang\""
  done

  # Always include private preset for git dependency tracking
  presets="$presets, \"github>$ORG/engineering-standards//renovate/private\""

  cat <<JSON
{
  "\$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [$presets]
}
JSON
}

generate_linter_workflow() {
  local scope="$1"
  cat <<YAML
name: Lint

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  lint:
    uses: $ORG/engineering-standards/.github/workflows/claude-linter.yml@main
    with:
      rule_scope: "$scope"
    secrets:
      ANTHROPIC_API_KEY: \${{ secrets.ANTHROPIC_API_KEY }}
      ENGINEERING_STANDARDS_READ: \${{ secrets.ENGINEERING_STANDARDS_READ }}
YAML
}

echo "Fetching repositories for org: $ORG"
REPOS=$(gh repo list "$ORG" --no-archived --source --json name -q '.[].name' --limit 500)
TOTAL=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "Found $TOTAL repositories (excluding forks)"
echo ""
echo "Mode: renovate=always${WITH_AI:+ ai=yes}${RENOVATE_ONLY:+ (renovate-only)}${DRY_RUN:+ (dry-run)}"
echo ""

printf "%-6s %-40s %s\n" "STATUS" "REPOSITORY" "SCOPE"
printf "%-6s %-40s %s\n" "------" "----------------------------------------" "-----"

CREATED=0
SKIPPED=0
FAILED=0

for REPO in $REPOS; do
  FULL="$ORG/$REPO"

  SKIP=false
  for S in "${SKIP_REPOS[@]}"; do
    if [ "$REPO" = "$S" ]; then SKIP=true; break; fi
  done
  if $SKIP; then
    printf "SKIP   %-40s %s\n" "$FULL" "(in skip list)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  EXISTING=$(gh pr list --repo "$FULL" --head "$BRANCH" --state open --json number -q 'length' 2>/dev/null || echo "0")
  if [ "$EXISTING" -gt 0 ] 2>/dev/null; then
    printf "SKIP   %-40s %s\n" "$FULL" "(PR already open)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  TMPDIR=$(mktemp -d)
  if gh repo clone "$FULL" "$TMPDIR" -- --depth 1 --quiet 2>/dev/null; then
    SCOPE=$(detect_scope "$TMPDIR")
    LABEL="${SCOPE:-generic}"

    if [ -n "$DRY_RUN" ]; then
      printf "DRY    %-40s %s\n" "$FULL" "$LABEL"
      CREATED=$((CREATED + 1))
      rm -rf "$TMPDIR"
      continue
    fi

    cd "$TMPDIR"
    git checkout -b "$BRANCH" 2>/dev/null

    # --- Base (required): Renovate ---
    generate_renovate_json "$SCOPE" > renovate.json
    git add renovate.json

    # --- Optional: AI workflows ---
    if [ -n "$WITH_AI" ] && [ -z "$RENOVATE_ONLY" ]; then
      mkdir -p .github/workflows
      cp "$SYNC_SOURCE" .github/workflows/sync-standards.yml
      generate_linter_workflow "$SCOPE" > .github/workflows/lint.yml
      git add .github/workflows/sync-standards.yml .github/workflows/lint.yml
    fi

    if git diff --cached --quiet; then
      printf "SKIP   %-40s %s\n" "$FULL" "(already up to date)"
      SKIPPED=$((SKIPPED + 1))
    else
      PARTS="renovate"
      [ -n "$WITH_AI" ] && [ -z "$RENOVATE_ONLY" ] && PARTS="renovate + ai"

      git commit -m "chore: add engineering standards ($PARTS, $LABEL)" --quiet
      git push origin "$BRANCH" --quiet 2>/dev/null

      BODY="Automated rollout from [engineering-standards](https://github.com/$ORG/engineering-standards).

**Base (always included):**
- \`renovate.json\` – automated dependency updates via centralized Renovate"

      if [ -n "$WITH_AI" ] && [ -z "$RENOVATE_ONLY" ]; then
        BODY="$BODY

**AI workflows (optional):**
- \`lint.yml\` – Claude reviews PRs against the ruleset (scope: \`$LABEL\`)
- \`sync-standards.yml\` – syncs \`.cursor/rules/\` and \`CLAUDE.md\` weekly"
      fi

      BODY="$BODY

Detected scope: **$LABEL**"

      gh pr create \
        --repo "$FULL" \
        --head "$BRANCH" \
        --title "chore: add engineering standards ($PARTS)" \
        --body "$BODY" \
        --no-maintainer-edit \
        2>/dev/null

      printf "OK     %-40s %s\n" "$FULL" "$LABEL"
      CREATED=$((CREATED + 1))
    fi

    cd - > /dev/null
  else
    printf "FAIL   %-40s %s\n" "$FULL" "(clone failed)"
    FAILED=$((FAILED + 1))
  fi

  rm -rf "$TMPDIR"
done

echo ""
echo "Done. Created: $CREATED | Skipped: $SKIPPED | Failed: $FAILED"
