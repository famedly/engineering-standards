CREATE TABLE IF NOT EXISTS repo_sync_status (
    repo_id         BIGINT PRIMARY KEY,
    repo_full_name  TEXT NOT NULL,
    installation_id BIGINT NOT NULL,
    last_sync_sha   TEXT,
    last_sync_at    TIMESTAMPTZ,
    detected_scopes TEXT[] NOT NULL DEFAULT '{}',
    config          JSONB NOT NULL DEFAULT '{}',
    pinned_version  TEXT NOT NULL DEFAULT 'latest',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_repo_sync_installation ON repo_sync_status(installation_id);

CREATE TABLE IF NOT EXISTS review_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_id         BIGINT NOT NULL REFERENCES repo_sync_status(repo_id) ON DELETE CASCADE,
    pr_number       INTEGER NOT NULL,
    head_sha        TEXT NOT NULL,
    errors_count    INTEGER NOT NULL DEFAULT 0,
    warnings_count  INTEGER NOT NULL DEFAULT 0,
    rules_applied   TEXT[] NOT NULL DEFAULT '{}',
    model           TEXT,
    tokens_used     INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_review_repo_pr ON review_results(repo_id, pr_number);

CREATE TABLE IF NOT EXISTS audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_id     BIGINT REFERENCES repo_sync_status(repo_id) ON DELETE SET NULL,
    action      TEXT NOT NULL,
    trigger     TEXT NOT NULL,
    details     JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_repo ON audit_log(repo_id);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);
