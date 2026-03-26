//! Detects flake.lock state in consumer repos.
//!
//! Reads `flake.lock` and extracts the `engineering-standards` input revision
//! and narHashes. Compares with the current HEAD of the standards repo to
//! determine if the lock is outdated.

use snafu::ResultExt;

use crate::db;
use crate::error::{self, Result};
use crate::module::WebhookContext;

const FLAKE_LOCK_PATH: &str = "flake.lock";
const STANDARDS_INPUT_NAME: &str = "engineering-standards";

/// Length for truncated SHA prefixes used in comparisons and display.
const SHA_SHORT_LEN: usize = 12;

/// Called on push to main in any repo. Reads flake.lock and updates DB.
#[tracing::instrument(skip_all, name = "flake::on_push")]
pub async fn on_push(ctx: &WebhookContext) -> Result<()> {
    let repo_full = ctx.repo_full_name().unwrap_or_default();
    let Some((owner, repo)) = repo_full.split_once('/') else {
        return Ok(());
    };

    let github = ctx.github().await?;
    let repo_id = get_repo_id(&github, owner, repo).await?;

    db::upsert_repo_status(
        &ctx.state.db,
        repo_id,
        &repo_full,
        ctx.installation_id as i64,
    )
    .await?;

    read_and_update_flake_lock(
        &ctx.state.db,
        &ctx.state.config,
        &github,
        owner,
        repo,
        repo_id,
    )
    .await
}

/// Called when the App is installed on a repo.
#[tracing::instrument(skip_all, name = "flake::on_installation")]
pub async fn on_installation(ctx: &WebhookContext) -> Result<()> {
    let repos = ctx
        .payload
        .get("repositories")
        .or_else(|| ctx.payload.get("repositories_added"))
        .and_then(|r| r.as_array())
        .cloned()
        .unwrap_or_default();

    let github = ctx.github().await?;

    for repo in &repos {
        let repo_id = repo.get("id").and_then(serde_json::Value::as_i64).unwrap_or(0);
        let full_name = repo
            .get("full_name")
            .and_then(|n| n.as_str())
            .unwrap_or_default();

        if let Err(e) = db::upsert_repo_status(
            &ctx.state.db,
            repo_id,
            full_name,
            ctx.installation_id as i64,
        )
        .await
        {
            tracing::warn!(repo = full_name, error = %e, "failed to upsert repo on installation");
            continue;
        }

        if let Some((owner, repo_name)) = full_name.split_once('/')
            && let Err(e) = read_and_update_flake_lock(
                &ctx.state.db,
                &ctx.state.config,
                &github,
                owner,
                repo_name,
                repo_id,
            )
            .await
            {
                tracing::debug!(repo = full_name, error = %e, "no flake.lock found");
            }
    }

    Ok(())
}

/// Scans a single repo's flake.lock and updates the DB (without creating bump PRs).
///
/// Used by the dashboard compliance scan.
pub async fn scan_repo_compliance(
    db: &sqlx::PgPool,
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    repo_id: i64,
) -> Result<()> {
    let repo_full = format!("{owner}/{repo}");
    let Some((flake_version, input_rev)) =
        fetch_and_parse_flake_lock(db, github, owner, repo, repo_id, &repo_full).await?
    else {
        return Ok(());
    };

    db::update_flake_status(db, repo_id, true, flake_version.as_deref(), input_rev.as_deref())
        .await?;

    tracing::info!(repo = %repo_full, ?flake_version, ?input_rev, "scanned flake status");
    Ok(())
}

async fn read_and_update_flake_lock(
    db: &sqlx::PgPool,
    config: &crate::config::Config,
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    repo_id: i64,
) -> Result<()> {
    let repo_full = format!("{owner}/{repo}");
    let Some((flake_version, input_rev)) =
        fetch_and_parse_flake_lock(db, github, owner, repo, repo_id, &repo_full).await?
    else {
        return Ok(());
    };

    db::update_flake_status(db, repo_id, true, flake_version.as_deref(), input_rev.as_deref())
        .await?;

    tracing::info!(repo = %repo_full, ?flake_version, ?input_rev, "updated flake status");

    if let Some(rev) = &input_rev {
        let current_head = get_standards_head(github, config).await?;
        if rev != &current_head {
            tracing::info!(
                repo = %repo_full,
                lock_rev = %rev,
                head_rev = %current_head,
                "flake.lock is outdated, creating bump PR",
            );
            if let Err(e) =
                super::updater::create_flake_bump_pr(github, owner, repo, rev, &current_head).await
            {
                tracing::error!(repo = %repo_full, error = %e, "flake bump PR failed");
            }
        }
    }

    Ok(())
}

/// Fetches `flake.lock`, parses the standards input, and handles the
/// "not found" / "no standards input" cases centrally.
///
/// Returns `None` when no flake.lock exists (DB is updated to reflect this).
/// Returns `Some((version, rev))` when parsing succeeds.
async fn fetch_and_parse_flake_lock(
    db: &sqlx::PgPool,
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    repo_id: i64,
    repo_full: &str,
) -> Result<Option<(Option<String>, Option<String>)>> {
    let flake_lock = match fetch_flake_lock(github, owner, repo).await {
        Ok(lock) => lock,
        Err(e) => {
            tracing::info!(repo = %repo_full, error = %e, "no flake.lock found");
            if let Err(e) = db::update_flake_status(db, repo_id, false, None, None).await {
                tracing::warn!(error = %e, "failed to clear flake status");
            }
            return Ok(None);
        }
    };

    let (flake_version, input_rev) = parse_standards_input(&flake_lock);

    if input_rev.is_none() {
        log_missing_standards_input(&flake_lock, repo_full);
    }

    Ok(Some((flake_version, input_rev)))
}

/// Logs diagnostic info when `flake.lock` exists but contains no
/// engineering-standards input.
fn log_missing_standards_input(flake_lock: &serde_json::Value, repo_full: &str) {
    let root_inputs: Vec<String> = flake_lock
        .get("nodes")
        .and_then(|n| n.get("root"))
        .and_then(|r| r.get("inputs"))
        .and_then(|i| i.as_object())
        .map(|o| o.iter().map(|(k, v)| format!("{k} → {v}")).collect())
        .unwrap_or_default();
    let node_names: Vec<String> = flake_lock
        .get("nodes")
        .and_then(|n| n.as_object())
        .map(|o| o.keys().cloned().collect())
        .unwrap_or_default();
    tracing::warn!(
        repo = %repo_full,
        ?root_inputs,
        ?node_names,
        "flake.lock found but no '{}' input",
        STANDARDS_INPUT_NAME,
    );
}

/// Fetches and decodes `flake.lock` from a repo.
async fn fetch_flake_lock(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
) -> Result<serde_json::Value> {
    let content = github
        .repos(owner, repo)
        .get_content()
        .path(FLAKE_LOCK_PATH)
        .r#ref("HEAD")
        .send()
        .await
        .context(error::GitHub)?;

    let text = content
        .items
        .first()
        .ok_or_else(|| error::NotFound.build())?
        .decoded_content()
        .ok_or_else(|| {
            error::BadRequest {
                message: "could not decode flake.lock".to_owned(),
            }
            .build()
        })?;

    serde_json::from_str(&text).whatever_context("parsing flake.lock")
}

/// Extracts the engineering-standards input version and rev from flake.lock.
///
/// Follows the root node's input mapping to resolve the actual node name,
/// which may differ from the input name when Nix deduplicates nodes (e.g.
/// `engineering-standards_2`).
///
/// Returns `(version_tag_or_none, git_rev)`.
fn parse_standards_input(lock: &serde_json::Value) -> (Option<String>, Option<String>) {
    let Some(nodes) = lock.get("nodes") else {
        return (None, None);
    };

    // The root node's `inputs` maps input names to node names. These can
    // differ when Nix deduplicates transitive inputs (e.g. the node may be
    // called `engineering-standards_2`).
    let node_name = nodes
        .get("root")
        .and_then(|root| root.get("inputs"))
        .and_then(|inputs| inputs.get(STANDARDS_INPUT_NAME))
        .and_then(|v| v.as_str())
        .unwrap_or(STANDARDS_INPUT_NAME);

    tracing::debug!(
        input_name = STANDARDS_INPUT_NAME,
        resolved_node = node_name,
        "resolved flake.lock node name",
    );

    let Some(standards_node) = nodes.get(node_name) else {
        tracing::warn!(
            node_name,
            "node not found in flake.lock despite being listed",
        );
        return (None, None);
    };

    let has_locked = standards_node.get("locked").is_some();
    let locked_keys: Vec<String> = standards_node
        .get("locked")
        .and_then(|l| l.as_object())
        .map(|o| o.keys().cloned().collect())
        .unwrap_or_default();

    tracing::info!(
        node_name,
        has_locked,
        ?locked_keys,
        node_type = ?standards_node.get("locked").and_then(|l| l.get("type")).and_then(|t| t.as_str()),
        "engineering-standards node details",
    );

    let locked = standards_node.get("locked");
    let lock_type = locked
        .and_then(|l| l.get("type"))
        .and_then(|t| t.as_str())
        .unwrap_or("unknown");

    let rev = locked
        .and_then(|l| l.get("rev"))
        .and_then(|r| r.as_str())
        .map(|s| s[..std::cmp::min(SHA_SHORT_LEN, s.len())].to_string());

    // For path-type inputs (local development), use a truncated narHash as
    // a fingerprint since there is no git revision.
    let rev = rev.or_else(|| {
        if lock_type == "path" {
            locked
                .and_then(|l| l.get("narHash"))
                .and_then(|h| h.as_str())
                .map(|h| {
                    let short = h.strip_prefix("sha256-").unwrap_or(h);
                    format!("path:{}", &short[..std::cmp::min(8, short.len())])
                })
        } else {
            None
        }
    });

    let version = standards_node
        .get("original")
        .and_then(|o| o.get("ref"))
        .and_then(|r| r.as_str())
        .map(ToOwned::to_owned);

    tracing::info!(?rev, ?version, lock_type, "parsed standards input");

    (version, rev)
}

/// Gets the current HEAD commit of the engineering-standards repo.
pub async fn get_standards_head(
    github: &octocrab::Octocrab,
    config: &crate::config::Config,
) -> Result<String> {
    let r#ref = github
        .repos(&config.standards_repo_owner, &config.standards_repo_name)
        .get_ref(&octocrab::params::repos::Reference::Branch("main".into()))
        .await
        .context(error::GitHub)?;

    match &r#ref.object {
        octocrab::models::repos::Object::Commit { sha, .. } => {
            Ok(sha[..std::cmp::min(SHA_SHORT_LEN, sha.len())].to_string())
        }
        _ => snafu::whatever!("unexpected ref type"),
    }
}

async fn get_repo_id(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
) -> Result<i64> {
    let r = github.repos(owner, repo).get().await.context(error::GitHub)?;
    Ok(r.id.0 as i64)
}
