//! Dashboard API endpoints.
//!
//! **Re-detect** (`POST /api/repos/:id/redetect`) — re-runs scope detection
//! against the live GitHub repo tree and updates the DB.
//!
//! **Pin** — scans workflows/Dockerfiles for unpinned references and creates PRs.
//!
//! **Flake** — checks for flake.nix and can create a Nix setup PR.
//!
//! **Compliance** — scans all repos for flake status and creates bump PRs.

use axum::{
    extract::{Path, State},
    response::{Html, IntoResponse},
    Extension,
};
use crate::dashboard::auth::User;
use crate::db;
use crate::error::{self, Result};
use crate::module::Context;
use crate::modules::{flake, pin, scope};

const SVG_CHECK: &str = r#"<svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/></svg>"#;
const SVG_CROSS: &str = r#"<svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/></svg>"#;
const SVG_WARN: &str = r#"<svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/></svg>"#;
const SVG_LOCK: &str = r#"<svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clip-rule="evenodd"/></svg>"#;

fn escape_html(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#x27;")
}

fn success_badge(text: &str) -> String {
    let safe = escape_html(text);
    format!(r#"<span class="inline-flex items-center gap-1.5 text-green-700 text-xs font-medium">{SVG_CHECK}{safe}</span>"#)
}

fn error_badge(text: &str) -> String {
    let safe = escape_html(text);
    format!(r#"<span class="inline-flex items-center gap-1.5 text-red-600 text-xs font-medium">{SVG_CROSS}{safe}</span>"#)
}

/// Resolved repo context from a DB row.
struct RepoCtx {
    status: db::RepoSyncStatus,
    owner: String,
    repo_name: String,
}

impl RepoCtx {
    async fn load(db: &sqlx::PgPool, repo_id: i64) -> Result<Self> {
        let status = db::get_repo_status(db, repo_id)
            .await?
            .ok_or_else(|| error::NotFound.build())?;
        let (owner, repo_name) = status
            .repo_full_name
            .split_once('/')
            .ok_or_else(|| error::NotFound.build())?;
        Ok(Self {
            owner: owner.to_owned(),
            repo_name: repo_name.to_owned(),
            status,
        })
    }

    fn installation_id(&self) -> u64 {
        self.status.github_installation_id()
    }

    async fn github(&self, state: &Context) -> Result<octocrab::Octocrab> {
        state.installation_client(self.installation_id()).await
    }
}

// ── Re-detect scopes ─────────────────────────────────────────────────────────

/// `POST /api/repos/:id/redetect` — re-runs scope detection against GitHub.
#[tracing::instrument(skip_all, fields(%repo_id), name = "api::redetect_scopes")]
pub async fn redetect_scopes(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
) -> Result<impl IntoResponse> {
    let rctx = RepoCtx::load(&state.db, repo_id).await?;
    let github = rctx.github(&state).await?;

    let scopes = scope::detect_scopes_for_repo(&github, &rctx.owner, &rctx.repo_name).await?;
    let scope_strings = scope::scopes_to_strings(&scopes);
    db::update_scopes(&state.db, repo_id, &scope_strings).await?;

    let badges: String = if scope_strings.is_empty() {
        r#"<span class="text-xs text-gray-400 italic">none detected</span>"#.into()
    } else {
        scope_strings
            .iter()
            .map(|s| {
                let safe = escape_html(s);
                format!(
                    r#"<span class="bg-blue-50 text-blue-700 rounded-full px-2 py-0.5 text-xs font-medium">{safe}</span>"#
                )
            })
            .collect::<Vec<_>>()
            .join(" ")
    };

    Ok(Html(badges))
}

// ── Security: Status checks (lazy-loaded on page open) ───────────────────────

/// `GET /api/repos/:id/check-actions` — fast status check, no SHA resolution.
#[tracing::instrument(skip_all, fields(%repo_id), name = "api::check_actions")]
pub async fn check_actions(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
    Extension(user): Extension<User>,
) -> Result<impl IntoResponse> {
    let rctx = RepoCtx::load(&state.db, repo_id).await?;
    let github = rctx.github(&state).await?;
    let (files_found, unpinned) =
        match pin::actions::count_unpinned(&github, &rctx.owner, &rctx.repo_name).await {
            Ok(result) => result,
            Err(e) => {
                tracing::warn!(error = %e, repo = %rctx.status.repo_full_name, "actions check failed");
                (0, 0)
            }
        };

    let html = check_status_html(
        files_found,
        unpinned,
        "No workflow files",
        "action(s) need pinning",
        &format!("/api/repos/{repo_id}/pin-actions"),
        user.role.is_admin(),
    );
    Ok(Html(html))
}

/// `GET /api/repos/:id/check-docker` — fast status check for Docker images.
#[tracing::instrument(skip_all, fields(%repo_id), name = "api::check_docker")]
pub async fn check_docker(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
    Extension(user): Extension<User>,
) -> Result<impl IntoResponse> {
    let rctx = RepoCtx::load(&state.db, repo_id).await?;
    let github = rctx.github(&state).await?;
    let (files_found, unpinned) =
        match pin::docker::count_unpinned(&github, &rctx.owner, &rctx.repo_name).await {
            Ok(result) => result,
            Err(e) => {
                tracing::warn!(error = %e, repo = %rctx.status.repo_full_name, "docker check failed");
                (0, 0)
            }
        };

    let html = check_status_html(
        files_found,
        unpinned,
        "No Dockerfiles",
        "image(s) need pinning",
        &format!("/api/repos/{repo_id}/pin-docker"),
        user.role.is_admin(),
    );
    Ok(Html(html))
}

fn check_status_html(
    files_found: usize,
    unpinned: usize,
    no_files_label: &str,
    needs_pin_label: &str,
    pin_url: &str,
    is_admin: bool,
) -> String {
    let check_svg = SVG_CHECK;
    let warn_svg = SVG_WARN;
    let lock_svg = SVG_LOCK;

    if files_found == 0 {
        let safe = escape_html(no_files_label);
        return format!("<span class=\"text-xs text-gray-400\">{safe}</span>");
    }
    if unpinned == 0 {
        return format!(
            "<span class=\"inline-flex items-center gap-1 text-green-700 text-xs font-medium\">{check_svg}All pinned</span>"
        );
    }

    let status = format!(
        "<span class=\"inline-flex items-center gap-1 text-amber-600 text-xs font-medium\">\
           {warn_svg}{unpinned} {needs_pin_label}\
         </span>"
    );

    if !is_admin {
        return format!("<span class=\"inline-flex items-center gap-3\">{status}</span>");
    }

    let id = pin_url.replace('/', "-").trim_matches('-').to_owned();
    format!(
        "<span class=\"inline-flex items-center gap-3\">\
           {status}\
           <span id=\"pin-result-{id}\">\
             <button hx-post=\"{pin_url}\" hx-target=\"#pin-result-{id}\" hx-swap=\"outerHTML\" \
               class=\"inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-lg \
                      border border-amber-300 bg-amber-50 text-amber-700 hover:bg-amber-100 transition-colors\">\
               {lock_svg}Create pin PR\
             </button>\
           </span>\
         </span>"
    )
}

// ── Security: Pin Actions ─────────────────────────────────────────────────────

/// `POST /api/repos/:id/pin-actions` — scans workflows and creates a pinning PR.
#[tracing::instrument(skip_all, fields(%repo_id), name = "api::pin_actions")]
pub async fn pin_actions(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
) -> Result<impl IntoResponse> {
    let rctx = RepoCtx::load(&state.db, repo_id).await?;
    let github = rctx.github(&state).await?;

    let (files_found, findings) =
        pin::actions::scan_repo_workflows(&github, &rctx.owner, &rctx.repo_name).await?;
    let html = pin_result_html(
        files_found,
        &findings,
        "action(s)",
        "No workflow files found",
        pin::actions::create_pin_pr(&github, &rctx.owner, &rctx.repo_name, &findings).await,
        "pin actions PR failed",
    );
    Ok(Html(html))
}

// ── Security: Pin Docker ──────────────────────────────────────────────────────

/// `POST /api/repos/:id/pin-docker` — scans Dockerfiles and creates a pinning PR.
#[tracing::instrument(skip_all, fields(%repo_id), name = "api::pin_docker")]
pub async fn pin_docker(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
) -> Result<impl IntoResponse> {
    let rctx = RepoCtx::load(&state.db, repo_id).await?;
    let github = rctx.github(&state).await?;

    let (files_found, findings) =
        pin::docker::scan_repo_dockerfiles(&github, &rctx.owner, &rctx.repo_name).await?;
    let html = pin_result_html(
        files_found,
        &findings,
        "image(s)",
        "No Dockerfiles found",
        pin::docker::create_pin_pr(&github, &rctx.owner, &rctx.repo_name, &findings).await,
        "pin docker PR failed",
    );
    Ok(Html(html))
}

// ── Nix Flake Setup ───────────────────────────────────────────────────────────

/// `GET /api/repos/:id/check-flake` — lazy-loads whether `flake.nix` exists.
#[tracing::instrument(skip_all, fields(%repo_id), name = "api::check_flake")]
pub async fn check_flake(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
    Extension(user): Extension<User>,
) -> Result<impl IntoResponse> {
    let rctx = RepoCtx::load(&state.db, repo_id).await?;
    let github = rctx.github(&state).await?;

    let has_flake = github
        .repos(&rctx.owner, &rctx.repo_name)
        .get_content()
        .path("flake.nix")
        .r#ref("HEAD")
        .send()
        .await
        .is_ok();

    let has_lock = github
        .repos(&rctx.owner, &rctx.repo_name)
        .get_content()
        .path("flake.lock")
        .r#ref("HEAD")
        .send()
        .await
        .is_ok();

    let html = if has_flake && has_lock {
        success_badge("flake.nix + flake.lock present")
    } else if has_flake {
        format!(
            r#"<span class="inline-flex items-center gap-1 text-amber-600 text-xs font-medium">{SVG_WARN}flake.nix found — run <code>nix flake update</code> locally</span>"#
        )
    } else if user.role.is_admin() {
        let post_url = format!("/api/repos/{repo_id}/setup-flake");
        let target_id = "flake-setup-result";
        format!(
            "<span id=\"{target_id}\">\
               <button hx-post=\"{post_url}\" \
                       hx-target=\"#{target_id}\" \
                       hx-swap=\"outerHTML\" \
                       hx-disabled-elt=\"this\" \
                       class=\"htmx-loading-btn inline-flex items-center gap-1.5 text-xs font-medium \
                              px-2.5 py-1 rounded-lg border border-blue-300 bg-blue-50 \
                              text-blue-700 hover:bg-blue-100 transition-colors\">\
                 <svg class=\"htmx-indicator w-3.5 h-3.5 animate-spin shrink-0\" fill=\"none\" viewBox=\"0 0 24 24\">\
                   <circle class=\"opacity-25\" cx=\"12\" cy=\"12\" r=\"10\" stroke=\"currentColor\" stroke-width=\"4\"/>\
                   <path class=\"opacity-75\" fill=\"currentColor\" d=\"M4 12a8 8 0 018-8v8z\"/>\
                 </svg>\
                 Set up Nix flake\
               </button>\
             </span>"
        )
    } else {
        format!(
            r#"<span class="inline-flex items-center gap-1 text-gray-400 text-xs">{SVG_CROSS}No flake.nix</span>"#
        )
    };

    Ok(Html(html))
}

/// `POST /api/repos/:id/setup-flake` — creates a PR with a generated `flake.nix`.
#[tracing::instrument(skip_all, fields(%repo_id), name = "api::setup_flake")]
pub async fn setup_flake(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
) -> Result<impl IntoResponse> {
    let rctx = RepoCtx::load(&state.db, repo_id).await?;
    let github = rctx.github(&state).await?;

    let scopes = &rctx.status.detected_scopes;
    let flake_content = generate_flake_nix(&rctx.status.repo_full_name, scopes);

    let result = create_nix_setup_pr(
        &github,
        &rctx.owner,
        &rctx.repo_name,
        &flake_content,
        &rctx.status.repo_full_name,
    )
    .await;

    let html = match result {
        Ok(()) => success_badge("PR created — merge + run nix flake update locally"),
        Err(e) => {
            tracing::error!(repo = %rctx.status.repo_full_name, error = %e, "nix setup PR failed");
            error_badge("Failed — check logs")
        }
    };

    Ok(Html(html))
}

// ── Compliance: Scan All ──────────────────────────────────────────────────────

/// `POST /api/compliance/scan` — scans all tracked repos for flake.lock status.
#[tracing::instrument(skip_all, name = "api::scan_all")]
pub async fn scan_all_repos(
    State(state): State<Context>,
    Extension(user): Extension<User>,
) -> Result<impl IntoResponse> {
    let repos = db::list_all_repos(&state.db).await?;
    let mut scanned = 0usize;
    let mut errors = 0usize;

    let mut by_installation: std::collections::HashMap<i64, Vec<&db::RepoSyncStatus>> =
        std::collections::HashMap::new();
    for repo in &repos {
        by_installation
            .entry(repo.installation_id)
            .or_default()
            .push(repo);
    }

    for (installation_id, installation_repos) in &by_installation {
        let github = match state.installation_client(*installation_id as u64).await {
            Ok(g) => g,
            Err(e) => {
                tracing::warn!(error = %e, %installation_id, "failed to get installation client");
                errors += installation_repos.len();
                continue;
            }
        };

        for repo in installation_repos {
            let Some((owner, name)) = repo.owner_and_name() else {
                continue;
            };

            match flake::scan_repo_compliance(
                &state.db,
                &github,
                owner,
                name,
                repo.repo_id,
            )
            .await
            {
                Ok(()) => scanned += 1,
                Err(e) => {
                    tracing::warn!(error = %e, repo = %repo.repo_full_name, "scan failed");
                    errors += 1;
                }
            }
        }
    }

    let _ = db::insert_audit_entry(
        &state.db,
        None,
        "compliance_scan",
        &user.audit_identity(),
        &serde_json::json!({ "scanned": scanned, "errors": errors }),
    )
    .await;

    let html = format!(
        r#"<span class="inline-flex items-center gap-1.5 text-green-700 text-xs font-medium">{SVG_CHECK}Scanned {scanned} repos ({errors} errors). <a href="/dashboard" class="underline ml-1">Reload</a></span>"#
    );
    Ok(Html(html))
}

// ── Compliance: Dispatch Updates ──────────────────────────────────────────────

/// `POST /api/compliance/dispatch` — dispatches `repository_dispatch` events
/// to all integrated consumer repos, triggering their update workflow.
#[tracing::instrument(skip_all, name = "api::dispatch_updates")]
pub async fn dispatch_updates(
    State(state): State<Context>,
    Extension(_user): Extension<User>,
) -> Result<impl IntoResponse> {
    match flake::updater::dispatch_updates_to_all(&state).await {
        Ok(()) => Ok(Html(format!(
            r#"<span class="inline-flex items-center gap-1.5 text-green-700 text-xs font-medium">{SVG_CHECK}Update events dispatched. <a href="/dashboard" class="underline ml-1">Reload</a></span>"#
        ))),
        Err(e) => {
            tracing::error!(error = %e, "dispatch failed");
            Ok(Html(error_badge("Dispatch failed — check logs")))
        }
    }
}

// ── Compliance: Update All ────────────────────────────────────────────────────

/// `POST /api/compliance/update-all` — creates bump PRs for all outdated repos.
#[tracing::instrument(skip_all, name = "api::update_all")]
pub async fn update_all_repos(
    State(state): State<Context>,
    Extension(user): Extension<User>,
) -> Result<impl IntoResponse> {
    let repos = db::list_all_repos(&state.db).await?;
    let standards_full = state.config.standards_repo_full();

    let standards_repo = repos
        .iter()
        .find(|r| r.repo_full_name == standards_full);

    let current_head = if let Some(s) = standards_repo {
        let github = state.installation_client(s.github_installation_id()).await?;
        flake::get_standards_head(&github, &state.config).await?
    } else {
        return Ok(Html(
            r#"<span class="inline-flex items-center gap-1.5 text-red-600 text-xs font-medium">Standards repo not installed — cannot determine HEAD</span>"#.to_owned(),
        ));
    };

    let outdated: Vec<_> = repos
        .iter()
        .filter(|r| {
            r.repo_full_name != standards_full
                && r.flake_input_rev
                    .as_ref()
                    .is_some_and(|rev| rev != &current_head)
        })
        .collect();

    let total = outdated.len();
    let mut updated = 0usize;
    let mut errors = 0usize;

    for repo in &outdated {
        let Some((owner, name)) = repo.owner_and_name() else {
            continue;
        };

        let Ok(github) = state.installation_client(repo.github_installation_id()).await else {
            errors += 1;
            continue;
        };

        let current_rev = repo.flake_input_rev.as_deref().unwrap_or("unknown");
        match flake::updater::create_flake_bump_pr(
            &github,
            owner,
            name,
            current_rev,
            &current_head,
        )
        .await
        {
            Ok(()) => updated += 1,
            Err(e) => {
                tracing::warn!(error = %e, repo = %repo.repo_full_name, "bump PR failed");
                errors += 1;
            }
        }
    }

    let _ = db::insert_audit_entry(
        &state.db,
        None,
        "compliance_update_all",
        &user.audit_identity(),
        &serde_json::json!({ "total": total, "updated": updated, "errors": errors }),
    )
    .await;

    let html = format!(
        r#"<span class="inline-flex items-center gap-1.5 text-green-700 text-xs font-medium">{SVG_CHECK}Created {updated}/{total} bump PRs ({errors} errors)</span>"#
    );
    Ok(Html(html))
}

// ── Compliance: Update Single Repo ────────────────────────────────────────────

/// `POST /api/repos/:id/update-flake` — creates a bump PR for a single repo.
#[tracing::instrument(skip_all, fields(%repo_id), name = "api::update_flake")]
pub async fn update_flake(
    State(state): State<Context>,
    Path(repo_id): Path<i64>,
    Extension(user): Extension<User>,
) -> Result<impl IntoResponse> {
    let rctx = RepoCtx::load(&state.db, repo_id).await?;
    let github = rctx.github(&state).await?;

    let current_rev = rctx.status.flake_input_rev.as_deref().unwrap_or("unknown");
    let current_head = flake::get_standards_head(&github, &state.config).await?;

    if current_rev == current_head {
        return Ok(Html(success_badge("Already up to date")));
    }

    match flake::updater::create_flake_bump_pr(
        &github,
        &rctx.owner,
        &rctx.repo_name,
        current_rev,
        &current_head,
    )
    .await
    {
        Ok(()) => {
            let _ = db::insert_audit_entry(
                &state.db,
                Some(repo_id),
                "flake_bump",
                &user.audit_identity(),
                &serde_json::json!({ "from": current_rev, "to": current_head }),
            )
            .await;
            Ok(Html(success_badge("Bump PR created")))
        }
        Err(e) => {
            tracing::error!(error = %e, "flake bump PR failed");
            Ok(Html(error_badge("Failed — check logs")))
        }
    }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

fn pin_result_html<T>(
    files_found: usize,
    unpinned: &[T],
    unit: &str,
    no_files_msg: &str,
    result: Result<()>,
    log_msg: &str,
) -> String {
    if files_found == 0 {
        return format!(
            r#"<span class="inline-flex items-center gap-1.5 text-gray-400 text-xs">{no_files_msg}</span>"#
        );
    }
    if unpinned.is_empty() {
        return success_badge(&format!("All {files_found} file(s) already pinned"));
    }
    match result {
        Ok(()) => success_badge(&format!("PR created — {} {unit} pinned", unpinned.len())),
        Err(e) => {
            tracing::error!(error = %e, "{log_msg}");
            error_badge("Failed — check logs")
        }
    }
}

fn generate_flake_nix(repo_full: &str, scopes: &[String]) -> String {
    let description = repo_full.replace('/', " / ");
    let has = |s: &str| scopes.iter().any(|x| x == s);
    let is_flutter = has("flutter");
    let is_dart = has("dart") || is_flutter;
    let is_rust = has("rust");
    let is_ts = has("typescript");
    let is_python = has("python");

    let mut standards_parts = vec![
        "            checks.enable = true;".to_owned(),
        "            infrastructure = {".to_owned(),
        "              editorconfig = true;".to_owned(),
        "              dependabot = true;".to_owned(),
    ];
    if is_rust { standards_parts.push("              dependabotRust = true;".to_owned()); }
    if is_dart { standards_parts.push("              dependabotDart = true;".to_owned()); }
    if is_python { standards_parts.push("              dependabotPython = true;".to_owned()); }
    standards_parts.push("            };".to_owned());

    let mut rule_scopes = vec![];
    if is_rust { rule_scopes.push("\"rust\""); }
    if is_dart { rule_scopes.push("\"dart\""); }
    if is_ts { rule_scopes.push("\"typescript\""); }
    if is_python { rule_scopes.push("\"python\""); }
    if !rule_scopes.is_empty() {
        standards_parts.push(format!(
            "            rules = {{\n              enable = true;\n              extraScopes = [ {} ];\n            }};",
            rule_scopes.join(" ")
        ));
    }

    if is_rust || is_dart || is_ts || is_python {
        let mut linting = vec!["            linting = {".to_owned(), "              enable = true;".to_owned()];
        if is_rust { linting.push("              rust = true;".to_owned()); }
        if is_dart { linting.push(format!("              {} = true;", if is_flutter { "flutter" } else { "dart" })); }
        if is_ts { linting.push("              typescript = true;".to_owned()); }
        if is_python { linting.push("              python = true;".to_owned()); }
        linting.push("            };".to_owned());
        standards_parts.extend(linting);
    }

    if is_rust || is_dart || is_python {
        let mut hooks = vec!["            hooks = {".to_owned(), "              enable = true;".to_owned()];
        if is_rust { hooks.push("              rust = true;".to_owned()); }
        if is_dart { hooks.push("              dart = true;".to_owned()); }
        if is_python { hooks.push("              python = true;".to_owned()); }
        hooks.push("            };".to_owned());
        standards_parts.extend(hooks);
    }

    standards_parts.push("            ci = {".to_owned());
    standards_parts.push("              enable = true;".to_owned());
    standards_parts.push("              armRunners = true;".to_owned());
    standards_parts.push("            };".to_owned());

    let standards_block = standards_parts.join("\n");

    let rust_inputs = if is_rust {
        r#"    crane.url = "github:ipetkov/crane";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };"#
    } else {
        ""
    };

    let rust_perset = if is_rust {
        r#"
        {
          pkgs,
          system,
          ...
        }:"#
    } else {
        "{ pkgs, ... }:"
    };

    let rust_body = if is_rust {
        format!(r#"
        let
          toolchain = inputs.fenix.packages.${{system}}.stable.toolchain;
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;
          src = craneLib.cleanCargoSource ./.;
          commonArgs = {{
            inherit src;
            strictDeps = true;
          }};
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {{
          famedly.standards = {{
{standards_block}
          }};

          checks = {{
            clippy = craneLib.cargoClippy (commonArgs // {{
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-features --all-targets -- --deny warnings";
            }});
            fmt = craneLib.cargoFmt {{ inherit src; }};
            tests = craneLib.cargoNextest (commonArgs // {{ inherit cargoArtifacts; }});
          }};

          packages.default = craneLib.buildPackage (commonArgs // {{ inherit cargoArtifacts; }});

          devShells.default = pkgs.mkShell {{
            inputsFrom = [ (craneLib.devShell {{ }}) ];
            packages = with pkgs; [ cargo-watch cargo-edit ];
          }};
        }}"#)
    } else if is_dart {
        let sdk = if is_flutter { "pkgs.flutter" } else { "pkgs.dart" };
        format!(r#"
        {{
          famedly.standards = {{
{standards_block}
            dart = {{
              enable = true;
              flutter = {};
            }};
          }};

          devShells.default = pkgs.mkShell {{
            packages = [ {} ];
          }};
        }}"#, is_flutter, sdk)
    } else {
        format!(r#"
        {{
          famedly.standards = {{
{standards_block}
          }};
        }}"#)
    };

    format!(r#"{{
  description = "{description}";

  inputs = {{
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    engineering-standards.url = "github:famedly/engineering-standards";
{rust_inputs}
  }};

  outputs =
    {{ flake-parts, ... }}@inputs:
    flake-parts.lib.mkFlake {{ inherit inputs; }} {{
      imports = [ inputs.engineering-standards.flakeModules.default ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        {rust_perset}
        {rust_body};
    }};
}}"#)
}

async fn create_nix_setup_pr(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    flake_content: &str,
    repo_full: &str,
) -> Result<()> {
    use crate::github::pr::PrBuilder;

    PrBuilder::new(github, owner, repo, "engineering-standards/nix-setup")
        .commit_message("feat: add Nix flake for engineering-standards integration")
        .title("feat: add Nix flake for engineering-standards integration")
        .body(format!(
            "## Nix Flake Setup\n\n\
             This PR adds `flake.nix` to `{repo_full}`, enabling the Nix-first engineering standards workflow.\n\n\
             ### After merging\n\n\
             Run these commands locally:\n\n\
             ```bash\n\
             nix flake update                 # generate flake.lock\n\
             nix run .#regenerateStandards    # write managed files\n\
             nix flake check                  # verify everything passes\n\
             git add -A && git commit -m 'chore: init engineering standards'\n\
             ```\n\n\
             ### What changes\n\n\
             - CI becomes a single `nix flake check` step\n\
             - All config files are generated via `nix run .#regenerateStandards`\n\
             - Updates are delivered as flake-bump PRs\n"
        ))
        .file("flake.nix", flake_content)
        .execute()
        .await?;

    Ok(())
}
