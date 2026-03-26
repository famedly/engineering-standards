//! Review orchestration: triggers on PR events and dispatches AI review.

use secrecy::ExposeSecret;
use snafu::ResultExt;

use crate::db;
use crate::error::{self, Result};
use crate::module::WebhookContext;
use crate::modules::scope;

use super::claude;
use super::formatter;

const TRIGGER_PHRASE: &str = "@check-standards";

#[must_use]
pub fn is_review_trigger(payload: &serde_json::Value) -> bool {
    let is_pr_comment = payload
        .get("issue")
        .and_then(|i| i.get("pull_request"))
        .is_some();

    let body = payload
        .get("comment")
        .and_then(|c| c.get("body"))
        .and_then(|b| b.as_str())
        .unwrap_or("");

    is_pr_comment && body.contains(TRIGGER_PHRASE)
}

#[tracing::instrument(skip_all, name = "review::on_pull_request")]
pub async fn on_pull_request(ctx: &WebhookContext) -> Result<()> {
    let pr = ctx
        .payload
        .get("pull_request")
        .ok_or_else(|| error::BadRequest { message: "missing pull_request".to_owned() }.build())?;

    let pr_number = pr
        .get("number")
        .and_then(serde_json::Value::as_u64)
        .ok_or_else(|| error::BadRequest { message: "missing pull_request.number".to_owned() }.build())?;
    let head_sha = pr
        .get("head")
        .and_then(|h| h.get("sha"))
        .and_then(|s| s.as_str())
        .ok_or_else(|| error::BadRequest { message: "missing pull_request.head.sha".to_owned() }.build())?;

    if pr.get("draft").and_then(serde_json::Value::as_bool).unwrap_or(false) {
        tracing::info!(pr = pr_number, "skipping draft PR");
        return Ok(());
    }

    run_review(ctx, pr_number, head_sha).await
}

#[tracing::instrument(skip_all, name = "review::on_review_comment")]
pub async fn on_review_comment(ctx: &WebhookContext) -> Result<()> {
    let pr_number = ctx
        .payload
        .get("issue")
        .and_then(|i| i.get("number"))
        .and_then(serde_json::Value::as_u64)
        .ok_or_else(|| error::BadRequest { message: "missing issue number".to_owned() }.build())?;

    let github = ctx.github().await?;
    let repo_full = ctx.repo_full_name().unwrap_or_default();
    let (owner, repo) = repo_full.split_once('/').unwrap_or(("", &repo_full));

    let pr = github.pulls(owner, repo).get(pr_number).await.context(error::GitHub)?;
    run_review(ctx, pr_number, &pr.head.sha).await
}

#[tracing::instrument(skip_all, fields(%pr_number, %head_sha))]
async fn run_review(ctx: &WebhookContext, pr_number: u64, head_sha: &str) -> Result<()> {
    let repo_full = ctx.repo_full_name()
        .ok_or_else(|| error::BadRequest { message: "missing repository.full_name".to_owned() }.build())?;
    let (owner, repo) = repo_full.split_once('/')
        .ok_or_else(|| error::BadRequest { message: "invalid repository.full_name format".to_owned() }.build())?;

    tracing::info!("running AI review");

    let (github, token) = crate::github::installation_client_with_token(
        &ctx.state.github_app,
        ctx.installation_id,
    )
    .await?;
    let scopes = scope::detect_scopes_for_repo(&github, owner, repo).await?;
    let rules = load_rules(&ctx.state, &scopes).await?;
    let diff = fetch_pr_diff(&ctx.state.http_client, owner, repo, pr_number, token.expose_secret()).await?;

    let review = claude::review_diff(&ctx.state.http_client, ctx.state.config.anthropic_api_key_value(), &rules, &diff).await?;
    let conclusion = if review.errors > 0 { "failure" } else { "success" };

    formatter::post_check_run(&github, owner, repo, head_sha, &review, conclusion).await?;
    if !review.comments.is_empty() {
        formatter::post_pr_review(&github, owner, repo, pr_number, &review).await?;
    }

    let repo_id = ctx
        .payload
        .get("repository")
        .and_then(|r| r.get("id"))
        .and_then(serde_json::Value::as_i64)
        .ok_or_else(|| error::BadRequest { message: "missing repository.id".to_owned() }.build())?;
    let scope_names: Vec<String> = scopes.iter().map(ToString::to_string).collect();

    #[allow(clippy::cast_possible_truncation)]
    let pr_number_i32 = i32::try_from(pr_number).unwrap_or(i32::MAX);
    #[allow(clippy::cast_possible_truncation)]
    let errors_i32 = i32::try_from(review.errors).unwrap_or(i32::MAX);
    #[allow(clippy::cast_possible_truncation)]
    let warnings_i32 = i32::try_from(review.warnings).unwrap_or(i32::MAX);
    #[allow(clippy::cast_possible_truncation)]
    let tokens_i32 = i32::try_from(review.tokens_used).unwrap_or(i32::MAX);

    if let Err(e) = db::insert_review_result(db::NewReviewResult {
        pool: &ctx.state.db,
        repo_id,
        pr_number: pr_number_i32,
        head_sha,
        errors: errors_i32,
        warnings: warnings_i32,
        rules: &scope_names,
        model: Some(&review.model),
        tokens: Some(tokens_i32),
    })
    .await
    {
        tracing::warn!(error = %e, "failed to store review result");
    }

    if let Err(e) = db::insert_audit_entry(
        &ctx.state.db,
        Some(repo_id),
        "review",
        "webhook",
        &serde_json::json!({
            "pr": pr_number,
            "errors": review.errors,
            "warnings": review.warnings,
        }),
    )
    .await
    {
        tracing::warn!(error = %e, "failed to store audit entry");
    }

    tracing::info!(errors = review.errors, warnings = review.warnings, "review complete");
    Ok(())
}

async fn load_rules(state: &crate::module::Context, scopes: &[scope::Scope]) -> Result<String> {
    let github = &*state.github_app;
    let owner = &state.config.standards_repo_owner;
    let repo = &state.config.standards_repo_name;
    let mut rules = String::new();

    for path in &["00-system-persona.md", "01-documentation.md", "02-code-quality.md", "03-documentation-style.md", "04-logging.md"] {
        let full = format!("ai-rules/global/{path}");
        if let Ok(c) = fetch_file(github, owner, repo, &full).await {
            rules.push_str(&c);
            rules.push_str("\n\n");
        }
    }
    for scope in scopes {
        let path = format!("ai-rules/{}/00-code-quality.md", scope.as_str());
        if let Ok(c) = fetch_file(github, owner, repo, &path).await {
            rules.push_str(&c);
            rules.push_str("\n\n");
        }
    }
    Ok(rules)
}

async fn fetch_file(github: &octocrab::Octocrab, owner: &str, repo: &str, path: &str) -> Result<String> {
    crate::github::fetch_file_content(github, owner, repo, path, "main").await
}

async fn fetch_pr_diff(
    http_client: &reqwest::Client,
    owner: &str,
    repo: &str,
    pr_number: u64,
    token: &str,
) -> Result<String> {
    let url = format!("https://api.github.com/repos/{owner}/{repo}/pulls/{pr_number}");
    let resp = http_client
        .get(&url)
        .header("Accept", "application/vnd.github.v3.diff")
        .header("Authorization", format!("Bearer {token}"))
        .header("User-Agent", "engineering-standards-app")
        .send()
        .await
        .context(error::HttpClient)?;
    resp.text().await.context(error::HttpClient)
}
