//! Database access functions for repo tracking, reviews, and audit log.

use chrono::{DateTime, Utc};
use serde::Serialize;
use snafu::ResultExt;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{self, Result};

/// Tracked state of a repository within the engineering standards system.
#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct RepoSyncStatus {
    /// GitHub repository ID.
    pub repo_id: i64,
    /// Full repository name (`owner/repo`).
    pub repo_full_name: String,
    /// GitHub App installation ID that manages this repo.
    pub installation_id: i64,
    /// Detected language/ecosystem scopes (e.g. `["rust", "docker"]`).
    pub detected_scopes: Vec<String>,
    /// engineering-standards version from flake.lock; None if repo has no flake.
    pub flake_version: Option<String>,
    /// Git revision of the engineering-standards flake input.
    pub flake_input_rev: Option<String>,
    /// Whether the repo has a `flake.lock` file.
    pub has_flake_lock: bool,
    /// When we last read the flake.lock successfully.
    pub flake_last_seen: Option<DateTime<Utc>>,
    /// When this record was first created.
    pub created_at: DateTime<Utc>,
    /// When this record was last updated.
    pub updated_at: DateTime<Utc>,
}

impl RepoSyncStatus {
    /// Returns the installation ID as `u64` for the GitHub API.
    #[must_use]
    pub fn github_installation_id(&self) -> u64 {
        self.installation_id as u64
    }

    /// Splits `repo_full_name` into `(owner, repo)`.
    ///
    /// Returns `None` if the name doesn't contain a `/`.
    #[must_use]
    pub fn owner_and_name(&self) -> Option<(&str, &str)> {
        self.repo_full_name.split_once('/')
    }
}

/// Result of an AI code review on a pull request.
#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
#[allow(missing_docs)]
pub struct ReviewResult {
    pub id: Uuid,
    pub repo_id: i64,
    pub pr_number: i32,
    pub head_sha: String,
    pub errors_count: i32,
    pub warnings_count: i32,
    pub rules_applied: Vec<String>,
    pub model: Option<String>,
    pub tokens_used: Option<i32>,
    pub created_at: DateTime<Utc>,
}

/// Single entry in the audit log tracking app actions.
#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
#[allow(missing_docs)]
pub struct AuditEntry {
    pub id: Uuid,
    pub repo_id: Option<i64>,
    pub action: String,
    pub trigger: String,
    pub details: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

/// Upserts a repo's tracking record; creates if new, updates timestamps if existing.
#[tracing::instrument(skip_all, fields(%repo_id, %repo_full_name))]
pub async fn upsert_repo_status(
    pool: &PgPool,
    repo_id: i64,
    repo_full_name: &str,
    installation_id: i64,
) -> Result<RepoSyncStatus> {
    sqlx::query_as::<_, RepoSyncStatus>(
        r#"
        INSERT INTO repo_sync_status (repo_id, repo_full_name, installation_id)
        VALUES ($1, $2, $3)
        ON CONFLICT (repo_id) DO UPDATE SET
            repo_full_name = EXCLUDED.repo_full_name,
            installation_id = EXCLUDED.installation_id,
            updated_at = now()
        RETURNING *
        "#,
    )
    .bind(repo_id)
    .bind(repo_full_name)
    .bind(installation_id)
    .fetch_one(pool)
    .await
    .context(error::Database)
}

/// Replaces the `detected_scopes` array and bumps `updated_at`.
#[tracing::instrument(skip_all, fields(%repo_id))]
pub async fn update_scopes(pool: &PgPool, repo_id: i64, scopes: &[String]) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE repo_sync_status
        SET detected_scopes = $2, updated_at = now()
        WHERE repo_id = $1
        "#,
    )
    .bind(repo_id)
    .bind(scopes)
    .execute(pool)
    .await
    .context(error::Database)?;
    Ok(())
}

/// Called when the GitHub App is uninstalled from a repository.
#[tracing::instrument(skip_all, fields(%repo_id))]
pub async fn delete_repo_status(pool: &PgPool, repo_id: i64) -> Result<()> {
    sqlx::query("DELETE FROM repo_sync_status WHERE repo_id = $1")
        .bind(repo_id)
        .execute(pool)
        .await
        .context(error::Database)?;
    Ok(())
}

/// Returns `None` when the repo is not tracked.
pub async fn get_repo_status(pool: &PgPool, repo_id: i64) -> Result<Option<RepoSyncStatus>> {
    sqlx::query_as::<_, RepoSyncStatus>(
        "SELECT * FROM repo_sync_status WHERE repo_id = $1",
    )
    .bind(repo_id)
    .fetch_optional(pool)
    .await
    .context(error::Database)
}

/// Ordered by `repo_full_name` for stable dashboard rendering.
pub async fn list_all_repos(pool: &PgPool) -> Result<Vec<RepoSyncStatus>> {
    sqlx::query_as::<_, RepoSyncStatus>(
        "SELECT * FROM repo_sync_status ORDER BY repo_full_name",
    )
    .fetch_all(pool)
    .await
    .context(error::Database)
}

/// Scoped to a single GitHub App installation for webhook processing.
pub async fn list_repos_by_installation(
    pool: &PgPool,
    installation_id: i64,
) -> Result<Vec<RepoSyncStatus>> {
    sqlx::query_as::<_, RepoSyncStatus>(
        "SELECT * FROM repo_sync_status WHERE installation_id = $1 ORDER BY repo_full_name",
    )
    .bind(installation_id)
    .fetch_all(pool)
    .await
    .context(error::Database)
}

/// Arguments for [`insert_review_result`].
#[allow(missing_docs)]
pub struct NewReviewResult<'a> {
    pub pool: &'a PgPool,
    pub repo_id: i64,
    pub pr_number: i32,
    pub head_sha: &'a str,
    pub errors: i32,
    pub warnings: i32,
    pub rules: &'a [String],
    pub model: Option<&'a str>,
    pub tokens: Option<i32>,
}

/// Stores the result of an AI code review.
#[tracing::instrument(
    skip(record),
    fields(repo_id = record.repo_id, pr_number = record.pr_number)
)]
pub async fn insert_review_result(record: NewReviewResult<'_>) -> Result<ReviewResult> {
    let NewReviewResult {
        pool,
        repo_id,
        pr_number,
        head_sha,
        errors,
        warnings,
        rules,
        model,
        tokens,
    } = record;

    sqlx::query_as::<_, ReviewResult>(
        r#"
        INSERT INTO review_results
            (repo_id, pr_number, head_sha, errors_count, warnings_count, rules_applied, model, tokens_used)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *
        "#,
    )
    .bind(repo_id)
    .bind(pr_number)
    .bind(head_sha)
    .bind(errors)
    .bind(warnings)
    .bind(rules)
    .bind(model)
    .bind(tokens)
    .fetch_one(pool)
    .await
    .context(error::Database)
}

/// Lists the most recent review results for a repo, newest first.
pub async fn list_reviews_for_repo(
    pool: &PgPool,
    repo_id: i64,
    limit: i64,
) -> Result<Vec<ReviewResult>> {
    sqlx::query_as::<_, ReviewResult>(
        "SELECT * FROM review_results WHERE repo_id = $1 ORDER BY created_at DESC LIMIT $2",
    )
    .bind(repo_id)
    .bind(limit)
    .fetch_all(pool)
    .await
    .context(error::Database)
}

/// Records an action in the audit log for traceability.
#[tracing::instrument(skip_all, fields(?repo_id, %action))]
pub async fn insert_audit_entry(
    pool: &PgPool,
    repo_id: Option<i64>,
    action: &str,
    trigger: &str,
    details: &serde_json::Value,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO audit_log (repo_id, action, trigger, details)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(repo_id)
    .bind(action)
    .bind(trigger)
    .bind(details)
    .execute(pool)
    .await
    .context(error::Database)?;
    Ok(())
}

/// Updates the Nix flake tracking fields for a repo.
#[tracing::instrument(skip_all, fields(%repo_id))]
pub async fn update_flake_status(
    pool: &PgPool,
    repo_id: i64,
    has_flake_lock: bool,
    flake_version: Option<&str>,
    flake_input_rev: Option<&str>,
) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE repo_sync_status
        SET has_flake_lock = $2,
            flake_version = $3,
            flake_input_rev = $4,
            flake_last_seen = now(),
            updated_at = now()
        WHERE repo_id = $1
        "#,
    )
    .bind(repo_id)
    .bind(has_flake_lock)
    .bind(flake_version)
    .bind(flake_input_rev)
    .execute(pool)
    .await
    .context(error::Database)?;
    Ok(())
}

/// Lists audit log entries with pagination (newest first).
pub async fn list_audit_entries(
    pool: &PgPool,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditEntry>> {
    sqlx::query_as::<_, AuditEntry>(
        "SELECT * FROM audit_log ORDER BY created_at DESC LIMIT $1 OFFSET $2",
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await
    .context(error::Database)
}
