//! Formats review results into GitHub Check Runs and PR review comments.

use snafu::ResultExt;

use crate::error::{self, Result};
use super::claude::ReviewResult;

/// Creates a GitHub Check Run with the review summary.
#[tracing::instrument(skip_all, fields(%owner, %repo, %head_sha))]
pub async fn post_check_run(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    head_sha: &str,
    review: &ReviewResult,
    conclusion: &str,
) -> Result<()> {
    let summary = format!(
        "**Engineering Standards Review**\n\n{}\n\n| Metric | Count |\n|--------|-------|\n| Errors | {} |\n| Warnings | {} |\n| Model | {} |\n| Tokens | {} |",
        review.summary, review.errors, review.warnings, review.model, review.tokens_used,
    );

    let body = serde_json::json!({
        "name": "Engineering Standards Review",
        "head_sha": head_sha,
        "status": "completed",
        "conclusion": conclusion,
        "output": {
            "title": format!("{} error(s), {} warning(s)", review.errors, review.warnings),
            "summary": summary,
        }
    });

    let url = format!("/repos/{owner}/{repo}/check-runs");
    let _: serde_json::Value = github.post(url, Some(&body)).await.context(error::GitHub)?;

    Ok(())
}

/// Posts inline review comments on the PR.
#[tracing::instrument(skip_all, fields(%owner, %repo, %pr_number))]
pub async fn post_pr_review(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    pr_number: u64,
    review: &ReviewResult,
) -> Result<()> {
    let comments: Vec<serde_json::Value> = review
        .comments
        .iter()
        .map(|c| {
            serde_json::json!({
                "path": c.path,
                "line": c.line,
                "body": format!("**[{}]** {}", c.severity, c.message),
            })
        })
        .collect();

    if comments.is_empty() {
        return Ok(());
    }

    let event = if review.errors > 0 { "REQUEST_CHANGES" } else { "COMMENT" };

    let body = serde_json::json!({
        "body": format!(
            "<!-- engineering-standards-review -->\n## Engineering Standards Review\n\n{}\n\n{} error(s), {} warning(s)",
            review.summary, review.errors, review.warnings,
        ),
        "event": event,
        "comments": comments,
    });

    let url = format!("/repos/{owner}/{repo}/pulls/{pr_number}/reviews");
    let _: serde_json::Value = github.post(url, Some(&body)).await.context(error::GitHub)?;

    Ok(())
}
