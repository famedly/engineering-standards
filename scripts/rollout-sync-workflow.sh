#!/usr/bin/env bash
set -euo pipefail

# Distributes both the sync-standards.yml and claude-linter.yml workflows
# to all repositories in the GitHub organization. Language scope (Dart/Rust)
# is detected automatically from the repo contents.
#
# Prerequisites:
#   - gh CLI authenticated with an org-level PAT (repo + workflow scopes)
#   - The PAT must have write access to the target repositories
#
# Usage:
#   ./scripts/rollout-sync-workflow.sh <org>
#   ./scripts/rollout-sync-workflow.sh <org> --dry-run

ORG="${1:?Usage: $0 <org> [--dry-run]}"
DRY_RUN="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC_SOURCE="$REPO_ROOT/.github/workflows/sync-standards.yml"
LINTER_TEMPLATE="$REPO_ROOT/.github/workflows/claude-linter.yml"
BRANCH="chore/add-engineering-standards"
SKIP_REPOS=("engineering-standards" ".github" "nehws")

for f in "$SYNC_SOURCE" "$LINTER_TEMPLATE"; do
  if [ ! -f "$f" ]; then echo "Error: $f not found"; exit 1; fi
done

detect_scope() {
  local dir="$1"
  local scope=""
  [ -f "$dir/pubspec.yaml" ] && scope="dart"
  [ -f "$dir/Cargo.toml" ] && scope="${scope:+$scope }rust"
  echo "$scope"
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

    if [ "$DRY_RUN" = "--dry-run" ]; then
      printf "DRY    %-40s %s\n" "$FULL" "$LABEL"
      CREATED=$((CREATED + 1))
      rm -rf "$TMPDIR"
      continue
    fi

    cd "$TMPDIR"
    git checkout -b "$BRANCH" 2>/dev/null

    mkdir -p .github/workflows
    cp "$SYNC_SOURCE" .github/workflows/sync-standards.yml
    generate_linter_workflow "$SCOPE" > .github/workflows/lint.yml

    git add .github/workflows/sync-standards.yml .github/workflows/lint.yml
    if git diff --cached --quiet; then
      printf "SKIP   %-40s %s\n" "$FULL" "(already up to date)"
      SKIPPED=$((SKIPPED + 1))
    else
      git commit -m "chore: add engineering standards workflows ($LABEL)" --quiet
      git push origin "$BRANCH" --quiet 2>/dev/null

      gh pr create \
        --repo "$FULL" \
        --head "$BRANCH" \
        --title "chore: add engineering standards workflows" \
        --body "Adds two workflows from [engineering-standards](https://github.com/$ORG/engineering-standards):
- **lint.yml** – Claude reviews PRs against the ruleset (scope: \`$LABEL\`)
- **sync-standards.yml** – syncs \`.cursor/rules/\` and \`CLAUDE.md\` weekly

Detected scope: **$LABEL** (based on $([ -n "$SCOPE" ] && echo "project files" || echo "no pubspec.yaml or Cargo.toml found"))." \
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
