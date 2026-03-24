#!/usr/bin/env bash
set -euo pipefail

# Generates a dependabot.yml to stdout based on detected language scope.
# Used by both the rollout script and the sync-standards workflow.
#
# Usage: ./scripts/generate-dependabot.sh "dart rust python"

SCOPE="${1:-}"

cat <<'HEADER'
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
HEADER

for lang in $SCOPE; do
  case "$lang" in
    dart)
      cat <<'DART'

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
DART
      ;;
    rust)
      cat <<'RUST'

  - package-ecosystem: "cargo"
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
RUST
      ;;
    python)
      cat <<'PYTHON'

  - package-ecosystem: "pip"
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
PYTHON
      ;;
    docker)
      cat <<'DOCKER'

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "daily"
      timezone: "Europe/Berlin"
    open-pull-requests-limit: 10
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
DOCKER
      ;;
  esac
done
