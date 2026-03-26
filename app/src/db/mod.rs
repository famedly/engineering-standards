//! Database access layer — all SQL queries are centralized here.

mod repositories;

pub use repositories::{
    AuditEntry, NewReviewResult, RepoSyncStatus, ReviewResult, delete_repo_status, get_repo_status,
    insert_audit_entry, insert_review_result, list_all_repos, list_audit_entries,
    list_repos_by_installation, list_reviews_for_repo, update_flake_status, update_scopes,
    upsert_repo_status,
};
