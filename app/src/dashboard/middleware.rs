//! Authentication and authorization middleware for dashboard routes.
//!
//! Validates the tower-sessions session, extracts the [`User`], and injects
//! it into request extensions. Unauthenticated requests are redirected to
//! `/login`. Unauthorized users (role [`Role::Denied`]) receive a 403 page.
//! Write operations require [`Role::Admin`].

use axum::extract::{Request, State};
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Redirect, Response};
use tower_sessions::Session;

use crate::module::Context;

use super::auth::{refresh_role_if_stale, Role, User, SESSION_USER_KEY};

/// Middleware that ensures a valid authenticated session exists and the user
/// has at least viewer-level access.
///
/// - No session → redirect to `/login`.
/// - [`Role::Denied`] → `403 Forbidden`.
/// - Stale role (> 5 min) → re-evaluated via OIDC `UserInfo` endpoint.
/// - Access token expired/revoked → session flushed, redirect to `/login`.
/// - Otherwise the [`User`] is injected into request extensions.
pub async fn require_auth(
    State(state): State<Context>,
    session: Session,
    mut request: Request,
    next: Next,
) -> Response {
    let user: Option<User> = session.get(SESSION_USER_KEY).await.unwrap_or(None);

    match user {
        Some(mut user) if user.role.has_access() => {
            match refresh_role_if_stale(
                &mut user,
                &state.config,
                &state.userinfo_url,
                &state.http_client,
            )
            .await
            {
                Ok(()) if user.role.has_access() => {
                    let _ = session.insert(SESSION_USER_KEY, &user).await;
                    request.extensions_mut().insert(user);
                    next.run(request).await
                }
                Ok(()) => {
                    // Role was revoked since last check
                    tracing::info!(sub = %user.sub, "access denied after role re-evaluation");
                    (
                        StatusCode::FORBIDDEN,
                        [("content-type", "text/html; charset=utf-8")],
                        DENIED_HTML,
                    )
                        .into_response()
                }
                Err(()) => {
                    // Access token expired or revoked — force re-login
                    session.flush().await.ok();
                    Redirect::temporary("/login").into_response()
                }
            }
        }
        Some(_) => (
            StatusCode::FORBIDDEN,
            [("content-type", "text/html; charset=utf-8")],
            DENIED_HTML,
        )
            .into_response(),
        None => Redirect::temporary("/login").into_response(),
    }
}

const DENIED_HTML: &str = r#"<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Access Denied</title></head>
<body style="display:flex;justify-content:center;align-items:center;height:100vh;margin:0;font-family:system-ui,sans-serif;background:#111;color:#fff">
<div style="text-align:center">
<h1 style="font-size:2rem;margin-bottom:.5rem">Access Denied</h1>
<p style="color:#999">Your account is not authorized to access this dashboard.<br>Contact your administrator to request access.</p>
<a href="/logout" style="color:#60a5fa;text-decoration:underline">Log out</a>
</div>
</body>
</html>"#;

/// Middleware that requires [`Role::Admin`] on an already-authenticated request.
///
/// Must be layered **inside** `require_auth` so that the [`User`] extension is
/// guaranteed to exist.
pub async fn require_admin(
    request: Request,
    next: Next,
) -> Response {
    let is_admin = request
        .extensions()
        .get::<User>()
        .is_some_and(|u| u.role == Role::Admin);

    if is_admin {
        next.run(request).await
    } else {
        (
            StatusCode::FORBIDDEN,
            axum::Json(serde_json::json!({ "error": "Admin role required" })),
        )
            .into_response()
    }
}
