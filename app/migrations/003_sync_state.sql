-- Track the actual sync state of each repository's main branch.
--
-- States:
--   'unconfigured'   never had a sync PR (default for new installs)
--   'pr_open'        sync PR created/updated, awaiting merge
--   'in_sync'        last sync PR was merged; main branch matches config
--   'config_changed' was in sync, but config changed since merge → needs Apply

ALTER TABLE repo_sync_status
    ADD COLUMN IF NOT EXISTS pr_state TEXT NOT NULL DEFAULT 'unconfigured';
