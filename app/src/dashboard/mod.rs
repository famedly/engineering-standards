//! Dashboard module: OIDC auth, protected views, and middleware.

pub mod api;
pub mod auth;
pub mod middleware;
pub mod views;

use axum::Router;

use crate::module::Context;

/// Returns all dashboard-related routes.
///
/// Receives the application `state` so that the `require_auth` middleware can
/// be registered via [`axum::middleware::from_fn_with_state`], which is required
/// when the middleware handler extracts [`axum::extract::State`].
///
/// - **Public**: `/login`, `/auth/callback`, `/logout` — no auth needed.
/// - **Viewer** (any authenticated user): dashboard views + read-only status
///   checks (GET).
/// - **Admin** (users matching `OIDC_ROLE_CLAIM`/`OIDC_ADMIN_VALUES`): all
///   write operations that create PRs, trigger scans, or dispatch events (POST).
pub fn routes(state: Context) -> Router<Context> {
    let public = Router::new()
        .route("/login", axum::routing::get(auth::login))
        .route("/auth/callback", axum::routing::get(auth::callback))
        .route("/logout", axum::routing::get(auth::logout));

    let viewer = Router::new()
        .route("/dashboard", axum::routing::get(views::org_overview))
        .route(
            "/dashboard/repo/{repo_id}",
            axum::routing::get(views::repo_detail),
        )
        .route(
            "/api/repos/{repo_id}/check-actions",
            axum::routing::get(api::check_actions),
        )
        .route(
            "/api/repos/{repo_id}/check-docker",
            axum::routing::get(api::check_docker),
        )
        .route(
            "/api/repos/{repo_id}/check-flake",
            axum::routing::get(api::check_flake),
        )
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            middleware::require_auth,
        ));

    let admin = Router::new()
        // Audit log contains user identities and admin actions — admin-only.
        .route("/dashboard/audit", axum::routing::get(views::audit_log))
        .route(
            "/api/repos/{repo_id}/redetect",
            axum::routing::post(api::redetect_scopes),
        )
        .route(
            "/api/repos/{repo_id}/pin-actions",
            axum::routing::post(api::pin_actions),
        )
        .route(
            "/api/repos/{repo_id}/pin-docker",
            axum::routing::post(api::pin_docker),
        )
        .route(
            "/api/repos/{repo_id}/setup-flake",
            axum::routing::post(api::setup_flake),
        )
        .route(
            "/api/repos/{repo_id}/update-flake",
            axum::routing::post(api::update_flake),
        )
        .route(
            "/api/compliance/scan",
            axum::routing::post(api::scan_all_repos),
        )
        .route(
            "/api/compliance/update-all",
            axum::routing::post(api::update_all_repos),
        )
        .route(
            "/api/compliance/dispatch",
            axum::routing::post(api::dispatch_updates),
        )
        .layer(axum::middleware::from_fn(middleware::require_admin))
        .layer(axum::middleware::from_fn_with_state(
            state,
            middleware::require_auth,
        ));

    public.merge(viewer).merge(admin)
}
