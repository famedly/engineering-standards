#!/usr/bin/env bash
set -euo pipefail

# Pins all GitHub Actions references to full-length commit SHAs across
# all repositories in a GitHub organization using pinact. Creates PRs
# for each repo that has unpinned references.
#
# Converts:
#   uses: actions/checkout@v4
# to:
#   uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4
#
# Prerequisites:
#   - pinact (go install github.com/suzuki-shunsuke/pinact/v3/cmd/pinact@latest)
#   - gh CLI authenticated with org-level PAT (repo scope)
#
# Usage:
#   ./scripts/pin-actions.sh <org> [--dry-run]

command -v pinact >/dev/null 2>&1 || { echo "Error: pinact is not installed. Run: go install github.com/suzuki-shunsuke/pinact/v3/cmd/pinact@v3.9.0"; exit 1; }

ORG="${1:?Usage: $0 <org> [--dry-run]}"
shift
DRY_RUN=""
for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY_RUN="true"
done

BRANCH="chore/pin-actions-sha"
SKIP_REPOS=("engineering-standards" ".github" "nehws")

echo "Fetching repositories for org: $ORG"
REPOS=$(gh repo list "$ORG" --no-archived --source --json name -q '.[].name' --limit 500)
TOTAL=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "Found $TOTAL repositories (excluding forks)"
echo ""
echo "Mode: pin-actions${DRY_RUN:+ (dry-run)}"
echo ""

printf "%-6s %-40s %s\n" "STATUS" "REPOSITORY" "FILES"
printf "%-6s %-40s %s\n" "------" "----------------------------------------" "-----"

CREATED=0
SKIPPED=0
FAILED=0

for REPO in $REPOS; do
  FULL="$ORG/$REPO"

  SKIP=false
  for S in "${SKIP_REPOS[@]}"; do
    [ "$REPO" = "$S" ] && { SKIP=true; break; }
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
    WORKFLOWS=$(find "$TMPDIR/.github/workflows" -name '*.yml' -o -name '*.yaml' 2>/dev/null || true)

    if [ -z "$WORKFLOWS" ]; then
      printf "SKIP   %-40s %s\n" "$FULL" "(no workflows)"
      SKIPPED=$((SKIPPED + 1))
      rm -rf "$TMPDIR"
      continue
    fi

    cd "$TMPDIR"
    pinact run 2>/dev/null || true

    FILES_CHANGED=$(git diff --name-only 2>/dev/null || true)
    FILES_COUNT=$(echo "$FILES_CHANGED" | grep -c '.' 2>/dev/null || echo "0")

    if [ "$FILES_COUNT" -eq 0 ]; then
      printf "SKIP   %-40s %s\n" "$FULL" "(already pinned)"
      SKIPPED=$((SKIPPED + 1))
      cd - > /dev/null
      rm -rf "$TMPDIR"
      continue
    fi

    FILES_SHORT=$(echo "$FILES_CHANGED" | xargs -I{} basename {} | tr '\n' ' ')

    if [ -n "$DRY_RUN" ]; then
      printf "DRY    %-40s %s\n" "$FULL" "$FILES_COUNT file(s): $FILES_SHORT"
      CREATED=$((CREATED + 1))
      cd - > /dev/null
      rm -rf "$TMPDIR"
      continue
    fi

    git checkout -b "$BRANCH" 2>/dev/null
    git add -A
    git commit -m "chore: pin GitHub Actions to full-length commit SHAs" --quiet
    git push origin "$BRANCH" --quiet 2>/dev/null

    PR_BODY="Pins all GitHub Actions references to full-length commit SHAs for supply chain security.

**Changed files ($FILES_COUNT):** $FILES_SHORT

After this is merged, Dependabot's \`github-actions\` ecosystem will keep the SHA pins updated automatically."

    gh pr create \
      --repo "$FULL" \
      --head "$BRANCH" \
      --title "chore: pin GitHub Actions to full-length commit SHAs" \
      --body "$PR_BODY" \
      --no-maintainer-edit \
      2>/dev/null

    printf "OK     %-40s %s\n" "$FULL" "$FILES_COUNT file(s): $FILES_SHORT"
    CREATED=$((CREATED + 1))
    cd - > /dev/null
  else
    printf "FAIL   %-40s %s\n" "$FULL" "(clone failed)"
    FAILED=$((FAILED + 1))
  fi

  rm -rf "$TMPDIR"
done

echo ""
echo "Done. Created: $CREATED | Skipped: $SKIPPED | Failed: $FAILED"
