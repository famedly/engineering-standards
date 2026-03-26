-- Migration 005: Track whether a repo has a flake.lock, independently of
-- whether it uses the engineering-standards flake input.

ALTER TABLE repo_sync_status
    ADD COLUMN IF NOT EXISTS has_flake_lock BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN repo_sync_status.has_flake_lock IS
    'true if the repo has a flake.lock file (detected by compliance scan)';
