-- Remove columns from the old sync module that is no longer used.
-- The Nix flake system now handles file generation; the app focuses on
-- compliance monitoring, AI reviews, and supply-chain pinning.

ALTER TABLE repo_sync_status
    DROP COLUMN IF EXISTS last_sync_sha,
    DROP COLUMN IF EXISTS last_sync_at,
    DROP COLUMN IF EXISTS config,
    DROP COLUMN IF EXISTS pinned_version,
    DROP COLUMN IF EXISTS pr_state;
