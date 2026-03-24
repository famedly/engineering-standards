#!/usr/bin/env bash
set -euo pipefail

# Pins all Docker image references to their SHA256 digests across
# all repositories in a GitHub organization. Creates PRs for each repo.
#
# Handles:
#   - Dockerfile:        FROM image:tag       → FROM image:tag@sha256:...
#   - docker-compose:    image: image:tag     → image: image:tag@sha256:...
#   - Already-pinned references are skipped
#
# Prerequisites:
#   - crane (brew install crane)
#   - gh CLI authenticated with org-level PAT (repo scope)
#
# Usage:
#   ./scripts/pin-docker-digests.sh <org> [--dry-run]

command -v crane >/dev/null 2>&1 || { echo "Error: crane is not installed. Run: brew install crane"; exit 1; }

ORG="${1:?Usage: $0 <org> [--dry-run]}"
shift
DRY_RUN=""
for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY_RUN="true"
done

BRANCH="chore/pin-docker-digests"
SKIP_REPOS=("engineering-standards" ".github" "nehws")
DIGEST_CACHE=""

resolve_digest() {
  local image="$1"

  local cached
  cached=$(echo "$DIGEST_CACHE" | grep "^${image}=" | head -1 | cut -d= -f2-)
  if [ -n "$cached" ]; then
    echo "$cached"
    return
  fi

  local digest
  digest=$(crane digest "$image" 2>/dev/null) || return 1
  DIGEST_CACHE="${DIGEST_CACHE}${image}=${digest}
"
  echo "$digest"
}

pin_dockerfile() {
  local file="$1"
  local changed=false

  local tmpfile
  tmpfile=$(mktemp)

  while IFS= read -r line; do
    if echo "$line" | grep -qiE '^\s*(FROM|#\s*syntax\s*=)' && ! echo "$line" | grep -q '@sha256:'; then
      local image
      image=$(echo "$line" | grep -oE '[a-zA-Z0-9_./-]+:[a-zA-Z0-9_.-]+' | head -1)
      if [ -n "$image" ]; then
        local digest
        if digest=$(resolve_digest "$image"); then
          line=$(echo "$line" | sed "s|${image}|${image}@${digest}|")
          changed=true
        fi
      fi
    fi
    echo "$line"
  done < "$file" > "$tmpfile"

  if $changed; then
    mv "$tmpfile" "$file"
    return 0
  else
    rm "$tmpfile"
    return 1
  fi
}

pin_compose() {
  local file="$1"
  local changed=false

  local tmpfile
  tmpfile=$(mktemp)

  while IFS= read -r line; do
    if echo "$line" | grep -qE '^\s*image:\s*' && ! echo "$line" | grep -q '@sha256:'; then
      local image
      image=$(echo "$line" | grep -oE '[a-zA-Z0-9_./-]+:[a-zA-Z0-9_.-]+' | head -1)
      if [ -n "$image" ]; then
        local digest
        if digest=$(resolve_digest "$image"); then
          line=$(echo "$line" | sed "s|${image}|${image}@${digest}|")
          changed=true
        fi
      fi
    fi
    echo "$line"
  done < "$file" > "$tmpfile"

  if $changed; then
    mv "$tmpfile" "$file"
    return 0
  else
    rm "$tmpfile"
    return 1
  fi
}

echo "Fetching repositories for org: $ORG"
REPOS=$(gh repo list "$ORG" --no-archived --source --json name -q '.[].name' --limit 500)
TOTAL=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "Found $TOTAL repositories (excluding forks)"
echo ""
echo "Mode: pin-docker-digests${DRY_RUN:+ (dry-run)}"
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
  CLONE_ERR=""
  if CLONE_ERR=$(gh repo clone "$FULL" "$TMPDIR" -- --depth 1 --quiet 2>&1); then
    DOCKERFILES=$(find "$TMPDIR" -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' 2>/dev/null | grep -v node_modules || true)
    COMPOSEFILES=$(find "$TMPDIR" -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' 2>/dev/null | grep -v node_modules || true)

    if [ -z "$DOCKERFILES" ] && [ -z "$COMPOSEFILES" ]; then
      printf "SKIP   %-40s %s\n" "$FULL" "(no Docker files)"
      SKIPPED=$((SKIPPED + 1))
      rm -rf "$TMPDIR"
      continue
    fi

    PINNED=0
    FILES_CHANGED=""

    for f in $DOCKERFILES; do
      if pin_dockerfile "$f"; then
        PINNED=$((PINNED + 1))
        FILES_CHANGED="${FILES_CHANGED} $(basename "$f")"
      fi
    done

    for f in $COMPOSEFILES; do
      if pin_compose "$f"; then
        PINNED=$((PINNED + 1))
        FILES_CHANGED="${FILES_CHANGED} $(basename "$f")"
      fi
    done

    if [ "$PINNED" -eq 0 ]; then
      printf "SKIP   %-40s %s\n" "$FULL" "(already pinned)"
      SKIPPED=$((SKIPPED + 1))
      rm -rf "$TMPDIR"
      continue
    fi

    if [ -n "$DRY_RUN" ]; then
      printf "DRY    %-40s %s\n" "$FULL" "$PINNED file(s):$FILES_CHANGED"
      CREATED=$((CREATED + 1))
      rm -rf "$TMPDIR"
      continue
    fi

    cd "$TMPDIR"

    git checkout -B "$BRANCH" 2>/dev/null

    git add -A
    git commit -m "chore: pin Docker images to SHA256 digests" --quiet

    if ! git push origin "$BRANCH" --quiet --force-with-lease 2>&1; then
      printf "FAIL   %-40s %s\n" "$FULL" "(push failed)"
      FAILED=$((FAILED + 1))
      cd - > /dev/null
      rm -rf "$TMPDIR"
      continue
    fi

    PR_BODY="Pins all Docker image references to their SHA256 digests for supply chain security.

**Changed files:** $PINNED ($FILES_CHANGED)

After this is merged, Dependabot's \`docker\` ecosystem will keep the digest pins updated automatically."

    if ! gh pr create \
      --repo "$FULL" \
      --head "$BRANCH" \
      --title "chore: pin Docker images to SHA256 digests" \
      --body "$PR_BODY" \
      --no-maintainer-edit \
      2>&1; then
      printf "FAIL   %-40s %s\n" "$FULL" "(PR create failed)"
      FAILED=$((FAILED + 1))
      cd - > /dev/null
      rm -rf "$TMPDIR"
      continue
    fi

    printf "OK     %-40s %s\n" "$FULL" "$PINNED file(s):$FILES_CHANGED"
    CREATED=$((CREATED + 1))
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
