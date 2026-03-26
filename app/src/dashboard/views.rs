//! Dashboard view handlers rendering askama templates.

use askama::Template;
use axum::extract::{Path, Query, State};
use axum::response::{Html, IntoResponse};
use axum::Extension;
use snafu::ResultExt;

use crate::dashboard::auth::User;
use crate::db;
use crate::error::{self, Result};
use crate::module::Context;
use crate::modules::flake;

#[derive(Template)]
#[template(path = "org_overview.html")]
struct OrgOverviewTemplate {
    version: String,
    standards_repo: String,
    current_head: Option<String>,
    repos: Vec<db::RepoSyncStatus>,
    total: usize,
    up_to_date: usize,
    outdated: usize,
    has_flake: usize,
    no_flake: usize,
    is_admin: bool,
}

/// Renders the organization-wide dashboard overview.
#[tracing::instrument(skip_all, name = "dashboard::org_overview")]
pub async fn org_overview(
    State(state): State<Context>,
    Extension(user): Extension<User>,
) -> Result<impl IntoResponse> {
    let all_repos = db::list_all_repos(&state.db).await?;

    let standards_full = state.config.standards_repo_full();
    let standards_installation = all_repos
        .iter()
        .find(|r| r.repo_full_name == standards_full);

    let current_head = if let Some(s) = standards_installation {
        match state.installation_client(s.github_installation_id()).await {
            Ok(github) => flake::get_standards_head(&github, &state.config).await.ok(),
            Err(_) => None,
        }
    } else {
        None
    };

    let repos: Vec<_> = all_repos
        .into_iter()
        .filter(|r| r.repo_full_name != standards_full)
        .collect();

    let total = repos.len();
    let up_to_date = repos
        .iter()
        .filter(|r| {
            matches!(
                (&r.flake_input_rev, &current_head),
                (Some(rev), Some(head)) if rev == head
            )
        })
        .count();
    let nix_integrated = repos
        .iter()
        .filter(|r| r.flake_input_rev.is_some())
        .count();
    let outdated = nix_integrated.saturating_sub(up_to_date);
    let has_flake = repos
        .iter()
        .filter(|r| r.has_flake_lock && r.flake_input_rev.is_none())
        .count();
    let no_flake = total.saturating_sub(nix_integrated).saturating_sub(has_flake);

    let tmpl = OrgOverviewTemplate {
        version: env!("CARGO_PKG_VERSION").into(),
        standards_repo: standards_full,
        current_head,
        repos,
        total,
        up_to_date,
        outdated,
        has_flake,
        no_flake,
        is_admin: user.role.is_admin(),
    };

    let html = tmpl.render().whatever_context("rendering org_overview template")?;
    Ok(Html(html))
}

#[derive(Template)]
#[template(path = "repo_detail.html")]
struct RepoDetailTemplate {
    version: String,
    repo: db::RepoSyncStatus,
    current_head: Option<String>,
    is_admin: bool,
}

/// Renders the detail page for a single tracked repository.
#[tracing::instrument(skip_all, fields(%repo_id), name = "dashboard::repo_detail")]
pub async fn repo_detail(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
    Extension(user): Extension<User>,
) -> Result<impl IntoResponse> {
    let repo = db::get_repo_status(&state.db, repo_id)
        .await?
        .ok_or_else(|| error::NotFound.build())?;

    let current_head = match state.installation_client(repo.github_installation_id()).await {
        Ok(github) => flake::get_standards_head(&github, &state.config).await.ok(),
        Err(_) => None,
    };

    let tmpl = RepoDetailTemplate {
        version: env!("CARGO_PKG_VERSION").into(),
        repo,
        current_head,
        is_admin: user.role.is_admin(),
    };

    let html = tmpl.render().whatever_context("rendering repo_detail template")?;
    Ok(Html(html))
}

/// Query parameters for the paginated audit log view.
#[derive(serde::Deserialize)]
pub struct AuditQuery {
    /// Page number (1-based, defaults to 1).
    pub page: Option<i64>,
}

#[derive(Template)]
#[template(path = "audit_log.html")]
struct AuditLogTemplate {
    version: String,
    entries: Vec<db::AuditEntry>,
    page: i64,
    has_more: bool,
}

/// Renders the paginated audit log view.
#[tracing::instrument(skip_all, name = "dashboard::audit_log")]
pub async fn audit_log(
    State(state): State<Context>,
    Query(query): Query<AuditQuery>,
) -> Result<impl IntoResponse> {
    let page = query.page.unwrap_or(1).max(1);
    let per_page = 50;
    let offset = (page - 1) * per_page;

    let entries = db::list_audit_entries(&state.db, per_page + 1, offset).await?;

    let has_more = entries.len() as i64 > per_page;
    let entries: Vec<_> = entries.into_iter().take(per_page as usize).collect();

    let tmpl = AuditLogTemplate {
        version: env!("CARGO_PKG_VERSION").into(),
        entries,
        page,
        has_more,
    };

    let html = tmpl.render().whatever_context("rendering audit_log template")?;
    Ok(Html(html))
}
