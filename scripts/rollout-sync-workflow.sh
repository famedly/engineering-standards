#!/usr/bin/env bash
set -euo pipefail

# Distributes engineering standards to all repositories in the GitHub
# organization. Dependabot config is always deployed (base/required).
# AI workflows (sync-standards, claude-linter) are opt-in via --with-ai.
#
# Prerequisites:
#   - gh CLI authenticated with an org-level PAT (repo + workflow scopes)
#   - The PAT must have write access to the target repositories
#
# Usage:
#   ./scripts/rollout-sync-workflow.sh <org> [--dry-run] [--with-ai]

ORG="${1:?Usage: $0 <org> [--dry-run] [--with-ai]}"
shift
DRY_RUN=""
WITH_AI=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="true" ;;
    --with-ai) WITH_AI="true" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GENERATE_DEPENDABOT="$REPO_ROOT/scripts/generate-dependabot.sh"
SYNC_SOURCE="$REPO_ROOT/.github/workflows/sync-standards.yml"
LINTER_TEMPLATE="$REPO_ROOT/.github/workflows/claude-linter.yml"
BRANCH="chore/add-engineering-standards"
SKIP_REPOS=("engineering-standards" ".github" "nehws")

detect_scope() {
  local dir="$1"
  local scope=""
  [ -f "$dir/pubspec.yaml" ] && scope="dart"
  [ -f "$dir/Cargo.toml" ] && scope="${scope:+$scope }rust"
  for f in "$dir/requirements.txt" "$dir/pyproject.toml" "$dir/setup.py" "$dir/Pipfile"; do
    if [ -f "$f" ]; then scope="${scope:+$scope }python"; break; fi
  done
  for f in "$dir/Dockerfile" "$dir/docker-compose.yml" "$dir/docker-compose.yaml"; do
    if [ -f "$f" ]; then scope="${scope:+$scope }docker"; break; fi
  done
  if find "$dir" -name '*.tf' -maxdepth 3 2>/dev/null | grep -q .; then
    scope="${scope:+$scope }terraform"
  fi
  if [ -f "$dir/Chart.yaml" ] || find "$dir" -name 'Chart.yaml' -maxdepth 3 2>/dev/null | grep -q .; then
    scope="${scope:+$scope }helm"
  fi
  echo "$scope"
}

generate_dependabot_yml() {
  local scope="$1"
  bash "$GENERATE_DEPENDABOT" "$scope"
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
echo "Mode: dependabot=always${WITH_AI:+ ai=yes}${DRY_RUN:+ (dry-run)}"
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
  CLONE_ERR=""
  if CLONE_ERR=$(gh repo clone "$FULL" "$TMPDIR" -- --depth 1 --quiet 2>&1); then
    SCOPE=$(detect_scope "$TMPDIR")
    LABEL="${SCOPE:-generic}"

    if [ -n "$DRY_RUN" ]; then
      printf "DRY    %-40s %s\n" "$FULL" "$LABEL"
      CREATED=$((CREATED + 1))
      rm -rf "$TMPDIR"
      continue
    fi

    cd "$TMPDIR"
    git checkout -B "$BRANCH" 2>/dev/null

    # --- Base (required): Dependabot ---
    mkdir -p .github
    generate_dependabot_yml "$SCOPE" > .github/dependabot.yml
    git add .github/dependabot.yml

    # --- Optional: AI workflows ---
    if [ -n "$WITH_AI" ]; then
      mkdir -p .github/workflows
      cp "$SYNC_SOURCE" .github/workflows/sync-standards.yml
      generate_linter_workflow "$SCOPE" > .github/workflows/lint.yml
      git add .github/workflows/sync-standards.yml .github/workflows/lint.yml
    fi

    if git diff --cached --quiet; then
      printf "SKIP   %-40s %s\n" "$FULL" "(already up to date)"
      SKIPPED=$((SKIPPED + 1))
    else
      PARTS="dependabot"
      [ -n "$WITH_AI" ] && PARTS="dependabot + ai"

      git commit -m "chore: add engineering standards ($PARTS, $LABEL)" --quiet

      if ! git push origin "$BRANCH" --quiet --force-with-lease 2>&1; then
        printf "FAIL   %-40s %s\n" "$FULL" "(push failed)"
        FAILED=$((FAILED + 1))
        cd - > /dev/null
        rm -rf "$TMPDIR"
        continue
      fi

      BODY="Automated rollout from [engineering-standards](https://github.com/$ORG/engineering-standards).

**Base (always included):**
- \`.github/dependabot.yml\` – automated dependency updates (Dependabot)
- Ecosystems: github-actions${SCOPE:+, $SCOPE}
- Grouped PRs: major updates separate from minor+patch
- Cooldown: 14 days"

      if [ -n "$WITH_AI" ]; then
        BODY="$BODY

**AI workflows (optional):**
- \`lint.yml\` – Claude reviews PRs against the ruleset (scope: \`$LABEL\`)
- \`sync-standards.yml\` – syncs \`.cursor/rules/\` and \`CLAUDE.md\` weekly"
      fi

      BODY="$BODY

Detected scope: **$LABEL**"

      if ! gh pr create \
        --repo "$FULL" \
        --head "$BRANCH" \
        --title "chore: add engineering standards ($PARTS)" \
        --body "$BODY" \
        --no-maintainer-edit \
        2>&1; then
        printf "FAIL   %-40s %s\n" "$FULL" "(PR create failed)"
        FAILED=$((FAILED + 1))
        cd - > /dev/null
        rm -rf "$TMPDIR"
        continue
      fi

      printf "OK     %-40s %s\n" "$FULL" "$LABEL"
      CREATED=$((CREATED + 1))
    fi

    cd - > /dev/null
  else
    CLONE_MSG=$(echo "$CLONE_ERR" | head -1)
    printf "FAIL   %-40s %s\n" "$FULL" "(clone failed: $CLONE_MSG)"
    FAILED=$((FAILED + 1))
  fi

  rm -rf "$TMPDIR"
done

echo ""
echo "Done. Created: $CREATED | Skipped: $SKIPPED | Failed: $FAILED"
