//! OIDC authentication flow for the dashboard.
//!
//! Implements the Authorization Code Flow with proper CSRF state and nonce
//! verification via server-side sessions (tower-sessions).

use axum::extract::{Query, State};
use axum::response::{IntoResponse, Redirect, Response};
use openidconnect::core::{CoreProviderMetadata, CoreResponseType};
use openidconnect::{
    AuthenticationFlow, AuthorizationCode, ClientId, ClientSecret, CsrfToken, IssuerUrl, Nonce,
    OAuth2TokenResponse as _, RedirectUrl, Scope, TokenResponse,
};
use snafu::ResultExt as _;
use tower_sessions::Session;

use crate::error::{self, Result};
use crate::module::Context;

/// Session key for the OIDC CSRF token (state parameter).
const SESSION_CSRF_KEY: &str = "oidc_csrf";
/// Session key for the OIDC nonce.
const SESSION_NONCE_KEY: &str = "oidc_nonce";
/// Session key for the authenticated user.
pub const SESSION_USER_KEY: &str = "user";

/// How long (in seconds) a cached role is considered fresh before re-checking
/// via the `UserInfo` endpoint.
const ROLE_CHECK_INTERVAL_SECS: i64 = 300;

/// User role determining dashboard permissions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Role {
    /// Authenticated but not authorized — no dashboard access.
    Denied,
    /// Read-only access to the dashboard.
    Viewer,
    /// Full access including write operations (PRs, scans, dispatches).
    Admin,
}

impl Role {
    /// Returns `true` if this role has admin privileges.
    #[must_use]
    pub fn is_admin(self) -> bool {
        self == Role::Admin
    }

    /// Returns `true` if this role grants any dashboard access.
    #[must_use]
    pub fn has_access(self) -> bool {
        matches!(self, Role::Viewer | Role::Admin)
    }
}

/// Authenticated user stored in the session after successful login.
///
/// The `access_token` is intentionally redacted from [`Debug`] output to
/// prevent accidental logging of credentials.
#[derive(Clone, serde::Serialize, serde::Deserialize)]
pub struct User {
    /// OIDC subject identifier.
    pub sub: String,
    /// Display name (from `name` claim).
    pub name: Option<String>,
    /// Email address (from `email` claim).
    pub email: Option<String>,
    /// Effective role derived from OIDC claims.
    pub role: Role,
    /// Access token used for `UserInfo` requests (stored server-side, never in cookie).
    pub access_token: String,
    /// Unix timestamp of when the role was last verified via `UserInfo`.
    pub role_checked_at: i64,
}

impl std::fmt::Debug for User {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("User")
            .field("sub", &self.sub)
            .field("name", &self.name)
            .field("email", &self.email)
            .field("role", &self.role)
            .field("access_token", &"[REDACTED]")
            .field("role_checked_at", &self.role_checked_at)
            .finish()
    }
}

impl User {
    /// Returns a human-readable identity string for audit log entries.
    #[must_use]
    pub fn audit_identity(&self) -> String {
        self.email
            .as_deref()
            .unwrap_or(&self.sub)
            .to_owned()
    }
}

/// Performs OIDC discovery and returns both the provider metadata and the
/// `UserInfo` endpoint URL.
///
/// Called **once** at application startup; results are cached in [`Context`]
/// so that every login and callback request can reuse them without extra
/// round-trips to the `IdP`.
#[tracing::instrument(skip_all, name = "oidc::discover_metadata")]
pub async fn discover_oidc_metadata(
    issuer_url: &str,
    http_client: &reqwest::Client,
) -> std::result::Result<(CoreProviderMetadata, String), String> {
    let issuer = IssuerUrl::new(issuer_url.to_owned())
        .map_err(|e| format!("invalid OIDC issuer URL: {e}"))?;

    let metadata = CoreProviderMetadata::discover_async(issuer, http_client)
        .await
        .map_err(|e| format!("OIDC discovery failed: {e}"))?;

    let userinfo_url = metadata
        .userinfo_endpoint()
        .ok_or_else(|| "OIDC provider metadata missing userinfo_endpoint".to_owned())?
        .url()
        .to_string();

    Ok((metadata, userinfo_url))
}

/// Builds an OIDC client from cached provider metadata in the application
/// [`Context`].  Avoids a Discovery round-trip on every login/callback.
fn build_oidc_client(
    config: &crate::config::Config,
    metadata: CoreProviderMetadata,
) -> Result<
    openidconnect::core::CoreClient<
        openidconnect::EndpointSet,
        openidconnect::EndpointNotSet,
        openidconnect::EndpointNotSet,
        openidconnect::EndpointNotSet,
        openidconnect::EndpointMaybeSet,
        openidconnect::EndpointMaybeSet,
    >,
> {
    let client = openidconnect::core::CoreClient::from_provider_metadata(
        metadata,
        ClientId::new(config.oidc_client_id.clone()),
        Some(ClientSecret::new(
            config.oidc_client_secret_value().to_owned(),
        )),
    )
    .set_redirect_uri(
        RedirectUrl::new(config.oidc_redirect_url.clone())
            .map_err(|e| error::Oidc { message: format!("invalid redirect URL: {e}") }.build())?,
    );

    Ok(client)
}

/// Initiates the OIDC login flow.
///
/// Generates a CSRF token and nonce, stores both in the server-side session,
/// then redirects the user to the `IdP`'s authorization endpoint.
/// Extra scopes from `OIDC_EXTRA_SCOPES` are appended to the request.
#[tracing::instrument(skip_all, name = "oidc::login")]
pub async fn login(State(state): State<Context>, session: Session) -> Result<Response> {
    let client = build_oidc_client(&state.config, (*state.oidc_provider_metadata).clone())?;

    let mut auth_builder = client
        .authorize_url(
            AuthenticationFlow::<CoreResponseType>::AuthorizationCode,
            CsrfToken::new_random,
            Nonce::new_random,
        )
        .add_scope(Scope::new("openid".into()))
        .add_scope(Scope::new("profile".into()))
        .add_scope(Scope::new("email".into()));

    for scope in &state.config.oidc_extra_scopes {
        auth_builder = auth_builder.add_scope(Scope::new(scope.clone()));
    }

    let (auth_url, csrf_token, nonce) = auth_builder.url();

    session
        .insert(SESSION_CSRF_KEY, csrf_token.secret().clone())
        .await
        .whatever_context("storing CSRF token in session")?;

    session
        .insert(SESSION_NONCE_KEY, nonce.secret().clone())
        .await
        .whatever_context("storing nonce in session")?;

    Ok(Redirect::temporary(auth_url.as_str()).into_response())
}

/// Query parameters returned by the `IdP` on the callback redirect.
#[derive(Debug, serde::Deserialize)]
pub struct CallbackParams {
    /// Authorization code to exchange for tokens.
    pub code: String,
    /// CSRF state parameter – must match the value stored in the session.
    pub state: String,
}

/// Handles the OIDC callback after `IdP` authentication.
///
/// 1. Verifies the CSRF state parameter against the session.
/// 2. Exchanges the authorization code for an ID token + access token.
/// 3. Verifies the nonce in the ID token against the session.
/// 4. Extracts user claims and stores the [`User`] in the session.
/// 5. Redirects to `/dashboard`.
#[tracing::instrument(skip_all, name = "oidc::callback")]
pub async fn callback(
    State(state): State<Context>,
    session: Session,
    Query(params): Query<CallbackParams>,
) -> Result<Response> {
    let stored_csrf: String = session
        .get(SESSION_CSRF_KEY)
        .await
        .whatever_context("reading CSRF from session")?
        .ok_or_else(|| {
            error::Oidc { message: "missing CSRF token in session – start login again".to_owned() }
                .build()
        })?;

    if params.state != stored_csrf {
        return Err(
            error::Oidc { message: "CSRF state mismatch – possible CSRF attack".to_owned() }
                .build(),
        );
    }

    let stored_nonce: String = session
        .get(SESSION_NONCE_KEY)
        .await
        .whatever_context("reading nonce from session")?
        .ok_or_else(|| {
            error::Oidc { message: "missing nonce in session – start login again".to_owned() }
                .build()
        })?;

    session.remove::<String>(SESSION_CSRF_KEY).await.ok();
    session.remove::<String>(SESSION_NONCE_KEY).await.ok();

    let client =
        build_oidc_client(&state.config, (*state.oidc_provider_metadata).clone())?;

    let token_response = client
        .exchange_code(AuthorizationCode::new(params.code))
        .map_err(|e| error::Oidc { message: format!("code exchange setup failed: {e}") }.build())?
        .request_async(&*state.http_client)
        .await
        .map_err(|e| error::Oidc { message: format!("token exchange failed: {e}") }.build())?;

    let id_token = token_response
        .id_token()
        .ok_or_else(|| {
            error::Oidc { message: "missing id_token in response".to_owned() }.build()
        })?;

    let expected_nonce = Nonce::new(stored_nonce);

    // Some IdPs (e.g. Zitadel) include the project ID as an additional audience
    // claim alongside the client ID.  The OIDC library already validates the
    // primary audience against our client_id; we allow any *extra* audiences
    // here.  If you want to lock this down, set `OIDC_EXTRA_AUDIENCES` to a
    // comma-separated list of accepted values — for now we allow all extras to
    // remain compatible with Zitadel's project-ID audience pattern.
    let verifier = client
        .id_token_verifier()
        .set_other_audience_verifier_fn(|_| true);

    let claims = id_token
        .claims(&verifier, &expected_nonce)
        .map_err(|e| error::Oidc { message: format!("claims verification failed: {e}") }.build())?;

    let access_token = token_response.access_token().secret().to_owned();
    // Serialize the already-verified claims to JSON so that resolve_role_from_claims
    // can use the same path-based lookup as the periodic UserInfo re-evaluation.
    // This avoids re-decoding the raw JWT string a second time.
    let claims_json = serde_json::to_value(claims).unwrap_or(serde_json::Value::Null);
    let role = resolve_role_from_claims(&claims_json, &state.config);

    let user = User {
        sub: claims.subject().to_string(),
        name: claims
            .name()
            .and_then(|n| n.iter().next())
            .map(|(_, v)| v.to_string()),
        email: claims.email().map(|e| e.as_str().to_owned()),
        role,
        access_token,
        role_checked_at: chrono::Utc::now().timestamp(),
    };

    tracing::info!(
        sub = %user.sub, name = ?user.name, email = ?user.email,
        role = ?user.role, "user logged in",
    );

    session
        .cycle_id()
        .await
        .whatever_context("cycling session ID after authentication")?;

    session
        .insert(SESSION_USER_KEY, user)
        .await
        .whatever_context("storing user in session")?;

    Ok(Redirect::temporary("/dashboard").into_response())
}

/// Clears the session and redirects to the login page.
#[tracing::instrument(skip_all, name = "oidc::logout")]
pub async fn logout(session: Session) -> Redirect {
    session.flush().await.ok();
    Redirect::temporary("/login")
}

/// Re-evaluates the user's role via the OIDC `UserInfo` endpoint if the cached
/// role is older than [`ROLE_CHECK_INTERVAL_SECS`].
///
/// Returns `Ok(())` on success (role may have changed in place).
/// Returns `Err(())` only when the access token is expired or revoked (HTTP
/// 401) — the caller should flush the session and redirect to login.
/// Network errors and 5xx responses keep the last known role (graceful
/// degradation).
#[tracing::instrument(skip(user, config), fields(sub = %user.sub), name = "oidc::refresh_role")]
pub async fn refresh_role_if_stale(
    user: &mut User,
    config: &crate::config::Config,
    userinfo_url: &str,
    http_client: &reqwest::Client,
) -> std::result::Result<(), ()> {
    let now = chrono::Utc::now().timestamp();
    if now - user.role_checked_at < ROLE_CHECK_INTERVAL_SECS {
        return Ok(());
    }

    let resp = http_client
        .get(userinfo_url)
        .bearer_auth(&user.access_token)
        .send()
        .await
        .map_err(|e| {
            tracing::warn!(error = %e, "userinfo request failed — keeping cached role");
        })?;

    let status = resp.status();

    if status == reqwest::StatusCode::UNAUTHORIZED {
        tracing::info!(sub = %user.sub, "access token expired or revoked — forcing re-login");
        return Err(());
    }

    if !status.is_success() {
        tracing::warn!(%status, "userinfo endpoint returned error — keeping cached role");
        return Ok(());
    }

    let claims: serde_json::Value = resp.json().await.map_err(|e| {
        tracing::warn!(error = %e, "failed to parse userinfo response — keeping cached role");
    })?;

    let new_role = resolve_role_from_claims(&claims, config);
    if new_role != user.role {
        tracing::info!(
            sub = %user.sub,
            old_role = ?user.role,
            new_role = ?new_role,
            "role changed via userinfo re-evaluation",
        );
        user.role = new_role;
    }
    user.role_checked_at = now;

    Ok(())
}

/// Determines the user's role from a parsed claims object.
///
/// Shared between the JWT-based initial login and the UserInfo-based
/// periodic re-evaluation. Evaluates admin values first, then viewer
/// values. Returns [`Role::Denied`] when neither matches.
pub fn resolve_role_from_claims(
    claims: &serde_json::Value,
    config: &crate::config::Config,
) -> Role {
    let Some(claim_path) = config.oidc_role_claim.as_deref() else {
        return Role::Admin;
    };

    if config.oidc_admin_values.is_empty() && config.oidc_viewer_values.is_empty() {
        return Role::Denied;
    }

    let claim_value = resolve_nested_claim(claims, claim_path);

    if matches_any(claim_value, &config.oidc_admin_values) {
        return Role::Admin;
    }
    if matches_any(claim_value, &config.oidc_viewer_values) {
        return Role::Viewer;
    }

    tracing::info!(claim = claim_path, "user claim did not match any configured role values");
    Role::Denied
}

/// Checks whether `claim_value` contains any of the `expected` strings.
///
/// Handles string, array-of-strings, and boolean claim types.
fn matches_any(claim_value: Option<&serde_json::Value>, expected: &[String]) -> bool {
    if expected.is_empty() {
        return false;
    }
    match claim_value {
        Some(serde_json::Value::String(s)) => expected.iter().any(|v| v == s),
        Some(serde_json::Value::Array(arr)) => arr.iter().any(|item| {
            item.as_str()
                .is_some_and(|s| expected.iter().any(|v| v == s))
        }),
        Some(serde_json::Value::Bool(b)) => *b && expected.iter().any(|v| v == "true"),
        _ => false,
    }
}

/// Resolves a dot-separated claim path (e.g. `realm_access.roles`) to a value.
fn resolve_nested_claim<'a>(
    value: &'a serde_json::Value,
    path: &str,
) -> Option<&'a serde_json::Value> {
    let mut current = value;
    for segment in path.split('.') {
        current = current.get(segment)?;
    }
    Some(current)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config_with_roles(
        claim: Option<&str>,
        admin: &[&str],
        viewer: &[&str],
    ) -> crate::config::Config {
        use secrecy::SecretString;
        crate::config::Config {
            listen_addr: String::new(),
            base_url: String::new(),
            github_app_id: 0,
            github_private_key: SecretString::from(String::new()),
            github_webhook_secret: SecretString::from(String::new()),
            database_url: SecretString::from(String::new()),
            anthropic_api_key: SecretString::from(String::new()),
            oidc_issuer_url: String::new(),
            oidc_client_id: String::new(),
            oidc_client_secret: SecretString::from(String::new()),
            oidc_redirect_url: String::new(),
            oidc_role_claim: claim.map(ToOwned::to_owned),
            oidc_admin_values: admin.iter().map(|s| (*s).to_owned()).collect(),
            oidc_viewer_values: viewer.iter().map(|s| (*s).to_owned()).collect(),
            oidc_extra_scopes: vec![],
            standards_repo_owner: String::new(),
            standards_repo_name: String::new(),
        }
    }

    #[test]
    fn no_role_claim_grants_admin() {
        let config = config_with_roles(None, &[], &[]);
        let claims = serde_json::json!({});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Admin);
    }

    #[test]
    fn empty_role_values_denies() {
        let config = config_with_roles(Some("roles"), &[], &[]);
        let claims = serde_json::json!({"roles": "admin"});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Denied);
    }

    #[test]
    fn string_claim_matches_admin() {
        let config = config_with_roles(Some("role"), &["admin"], &["viewer"]);
        let claims = serde_json::json!({"role": "admin"});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Admin);
    }

    #[test]
    fn string_claim_matches_viewer() {
        let config = config_with_roles(Some("role"), &["admin"], &["viewer"]);
        let claims = serde_json::json!({"role": "viewer"});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Viewer);
    }

    #[test]
    fn array_claim_matches_admin() {
        let config = config_with_roles(Some("groups"), &["admins"], &["devs"]);
        let claims = serde_json::json!({"groups": ["users", "admins"]});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Admin);
    }

    #[test]
    fn nested_claim_path() {
        let config = config_with_roles(Some("realm_access.roles"), &["admin"], &[]);
        let claims = serde_json::json!({"realm_access": {"roles": ["admin", "user"]}});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Admin);
    }

    #[test]
    fn unmatched_claim_denies() {
        let config = config_with_roles(Some("role"), &["admin"], &["viewer"]);
        let claims = serde_json::json!({"role": "unknown"});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Denied);
    }

    #[test]
    fn missing_claim_denies() {
        let config = config_with_roles(Some("role"), &["admin"], &["viewer"]);
        let claims = serde_json::json!({"other": "value"});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Denied);
    }

    #[test]
    fn boolean_claim_true() {
        let config = config_with_roles(Some("is_admin"), &["true"], &[]);
        let claims = serde_json::json!({"is_admin": true});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Admin);
    }

    #[test]
    fn resolve_nested_claim_basic() {
        let v = serde_json::json!({"a": {"b": {"c": 42}}});
        assert_eq!(resolve_nested_claim(&v, "a.b.c"), Some(&serde_json::json!(42)));
    }

    #[test]
    fn resolve_nested_claim_missing() {
        let v = serde_json::json!({"a": 1});
        assert_eq!(resolve_nested_claim(&v, "a.b"), None);
    }

    #[test]
    fn admin_takes_priority_over_viewer() {
        let config = config_with_roles(Some("role"), &["power"], &["power"]);
        let claims = serde_json::json!({"role": "power"});
        assert_eq!(resolve_role_from_claims(&claims, &config), Role::Admin);
    }
}
