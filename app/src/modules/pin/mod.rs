//! Supply-chain pinning module for GitHub Actions and Docker images.

pub mod actions;
pub mod docker;

use std::sync::Arc;

use crate::db;
use crate::error::Result;
use crate::module::{Module, WebhookContext};

struct PinModule;

#[async_trait::async_trait]
impl Module for PinModule {
    fn name(&self) -> &'static str {
        "pin"
    }

    async fn handle_webhook(&self, ctx: &WebhookContext) -> Result<bool> {
        handle_push(ctx).await
    }
}

/// Monitors workflow/Dockerfile changes and auto-pins on push to main.
pub fn create() -> Arc<dyn Module> {
    Arc::new(PinModule)
}

/// Called when workflow files or Dockerfiles change on push to main/master.
async fn handle_push(ctx: &WebhookContext) -> Result<bool> {
    match (ctx.event.as_str(), ctx.action.as_deref()) {
        ("push", _) => {
            let repo_full = ctx.repo_full_name().unwrap_or_default();
            if repo_full == ctx.state.config.standards_repo_full() {
                return Ok(false);
            }

            let ref_name = ctx.payload.get("ref").and_then(|r| r.as_str()).unwrap_or("");
            if !ref_name.ends_with("/main") && !ref_name.ends_with("/master") {
                return Ok(false);
            }

            let changed = changed_files(&ctx.payload);
            let has_workflows = changed.iter().any(|f| {
                f.starts_with(".github/workflows/") && f.ends_with(".yml")
            });
            let has_dockerfiles = changed.iter().any(|f| {
                f.contains("Dockerfile") || f.contains("docker-compose")
            });

            if has_workflows
                && let Err(e) = on_workflow_change(ctx).await
            {
                tracing::error!(error = %e, %repo_full, "actions pinning failed");
            }
            if has_dockerfiles
                && let Err(e) = on_dockerfile_change(ctx).await
            {
                tracing::error!(error = %e, %repo_full, "docker pinning failed");
            }

            Ok(has_workflows || has_dockerfiles)
        }
        _ => Ok(false),
    }
}

fn extract_repo_id(payload: &serde_json::Value) -> Option<i64> {
    payload
        .get("repository")
        .and_then(|r| r.get("id"))
        .and_then(serde_json::Value::as_i64)
}

fn changed_files(payload: &serde_json::Value) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let commits = payload
        .get("commits")
        .and_then(|c| c.as_array())
        .cloned()
        .unwrap_or_default();

    for commit in &commits {
        for key in &["added", "modified"] {
            if let Some(arr) = commit.get(key).and_then(|a| a.as_array()) {
                for item in arr {
                    if let Some(path) = item.as_str() {
                        seen.insert(path.to_owned());
                    }
                }
            }
        }
    }
    seen.into_iter().collect()
}

#[tracing::instrument(skip_all, name = "pin::on_workflow_change")]
async fn on_workflow_change(ctx: &WebhookContext) -> Result<()> {
    let repo_full = ctx.repo_full_name().unwrap_or_default();
    let (owner, repo) = repo_full.split_once('/').unwrap_or(("", &repo_full));
    let github = ctx.github().await?;

    let (files_found, findings) = actions::scan_repo_workflows(&github, owner, repo).await?;
    if files_found == 0 || findings.is_empty() {
        tracing::info!(%repo_full, "all actions pinned or no workflow files");
        return Ok(());
    }

    tracing::info!(%repo_full, count = findings.len(), "found unpinned actions");
    actions::create_pin_pr(&github, owner, repo, &findings).await?;

    let repo_id = extract_repo_id(&ctx.payload);
    let _ = db::insert_audit_entry(
        &ctx.state.db,
        repo_id,
        "pin_actions",
        "webhook",
        &serde_json::json!({ "findings": findings.len() }),
    )
    .await;

    Ok(())
}

#[tracing::instrument(skip_all, name = "pin::on_dockerfile_change")]
async fn on_dockerfile_change(ctx: &WebhookContext) -> Result<()> {
    let repo_full = ctx.repo_full_name().unwrap_or_default();
    let (owner, repo) = repo_full.split_once('/').unwrap_or(("", &repo_full));
    let github = ctx.github().await?;

    let (files_found, findings) = docker::scan_repo_dockerfiles(&github, owner, repo).await?;
    if files_found == 0 || findings.is_empty() {
        tracing::info!(%repo_full, "all docker images pinned or no Dockerfiles");
        return Ok(());
    }

    tracing::info!(%repo_full, count = findings.len(), "found unpinned docker images");
    docker::create_pin_pr(&github, owner, repo, &findings).await?;

    let repo_id = extract_repo_id(&ctx.payload);
    let _ = db::insert_audit_entry(
        &ctx.state.db,
        repo_id,
        "pin_docker",
        "webhook",
        &serde_json::json!({ "findings": findings.len() }),
    )
    .await;

    Ok(())
}
