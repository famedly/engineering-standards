-- Migration 002: Add Nix flake tracking fields to repo_sync_status.
--
-- flake_version: The engineering-standards version from the repo's flake.lock
--   (null = repo has not yet integrated the Nix flake)
-- flake_input_rev: The git revision of the engineering-standards flake input
--   (used to detect when the flake.lock is outdated)

ALTER TABLE repo_sync_status
    ADD COLUMN IF NOT EXISTS flake_version    TEXT,
    ADD COLUMN IF NOT EXISTS flake_input_rev  TEXT,
    ADD COLUMN IF NOT EXISTS flake_last_seen  TIMESTAMPTZ;

COMMENT ON COLUMN repo_sync_status.flake_version IS
    'engineering-standards version in flake.lock, null if repo has no flake';
COMMENT ON COLUMN repo_sync_status.flake_input_rev IS
    'git rev of the engineering-standards flake input';
COMMENT ON COLUMN repo_sync_status.flake_last_seen IS
    'when we last successfully read the flake.lock from this repo';
