//! Application configuration loaded from environment variables.

use secrecy::{ExposeSecret, SecretString};
use snafu::ResultExt;

use crate::error::Result;

/// Top-level application configuration.
#[derive(Debug, Clone)]
pub struct Config {
    /// Socket address to bind the HTTP server to (default `0.0.0.0:3000`).
    pub listen_addr: String,
    /// Public base URL used for CORS origin and redirects.
    pub base_url: String,

    /// GitHub App ID.
    pub github_app_id: u64,
    /// GitHub App private key (PEM format).
    pub github_private_key: SecretString,
    /// Webhook secret for HMAC-SHA256 verification.
    pub github_webhook_secret: SecretString,

    /// `PostgreSQL` connection string.
    pub database_url: SecretString,

    /// Anthropic API key for Claude-based code reviews.
    pub anthropic_api_key: SecretString,

    /// OIDC issuer URL for authentication.
    pub oidc_issuer_url: String,
    /// OIDC client ID.
    pub oidc_client_id: String,
    /// OIDC client secret.
    pub oidc_client_secret: SecretString,
    /// OIDC callback redirect URL.
    pub oidc_redirect_url: String,

    /// ID token claim used for role-based access control (e.g. `groups`,
    /// `roles`, `realm_access.roles`).  Supports dot-notation for nested
    /// claims.  When unset, every authenticated user is treated as admin
    /// (backwards compatible).
    pub oidc_role_claim: Option<String>,
    /// Claim values that grant **admin** access (read + write).
    pub oidc_admin_values: Vec<String>,
    /// Claim values that grant **viewer** access (read-only).  Users whose
    /// claim matches neither admin nor viewer values are denied entirely.
    pub oidc_viewer_values: Vec<String>,
    /// Additional `OAuth2` scopes requested during login (comma-separated).
    /// Required by some `IdPs` to include role/group claims in tokens.
    /// For Zitadel: `urn:zitadel:iam:org:projects:roles`
    pub oidc_extra_scopes: Vec<String>,

    /// Owner of the engineering-standards repository.
    pub standards_repo_owner: String,
    /// Name of the engineering-standards repository.
    pub standards_repo_name: String,
}

impl Config {
    /// Loads configuration from environment variables.
    ///
    /// Reads `GITHUB_PRIVATE_KEY_PATH` to load the key from a file, falling
    /// back to `GITHUB_PRIVATE_KEY` as a direct value.
    #[tracing::instrument(skip_all, name = "config::load")]
    pub fn from_env() -> Result<Self> {
        let private_key_path = std::env::var("GITHUB_PRIVATE_KEY_PATH").unwrap_or_default();
        let private_key = if private_key_path.is_empty() {
            env_var("GITHUB_PRIVATE_KEY")?
        } else {
            std::fs::read_to_string(&private_key_path)
                .whatever_context("reading GitHub App private key file")?
        };

        let app_id: u64 = env_var("GITHUB_APP_ID")?
            .parse()
            .whatever_context("GITHUB_APP_ID must be a valid u64")?;

        Ok(Self {
            listen_addr: std::env::var("LISTEN_ADDR")
                .unwrap_or_else(|_| "0.0.0.0:3000".into()),
            base_url: env_var("BASE_URL")?,
            github_app_id: app_id,
            github_private_key: SecretString::from(private_key),
            github_webhook_secret: SecretString::from(env_var("GITHUB_WEBHOOK_SECRET")?),
            database_url: SecretString::from(env_var("DATABASE_URL")?),
            anthropic_api_key: SecretString::from(env_var("ANTHROPIC_API_KEY")?),
            oidc_issuer_url: env_var("OIDC_ISSUER_URL")?,
            oidc_client_id: env_var("OIDC_CLIENT_ID")?,
            oidc_client_secret: SecretString::from(env_var("OIDC_CLIENT_SECRET")?),
            oidc_redirect_url: env_var("OIDC_REDIRECT_URL")?,
            oidc_role_claim: std::env::var("OIDC_ROLE_CLAIM").ok().filter(|s| !s.is_empty()),
            oidc_admin_values: parse_comma_list("OIDC_ADMIN_VALUES"),
            oidc_viewer_values: parse_comma_list("OIDC_VIEWER_VALUES"),
            oidc_extra_scopes: parse_comma_list("OIDC_EXTRA_SCOPES"),
            standards_repo_owner: env_var("STANDARDS_REPO_OWNER")?,
            standards_repo_name: env_var("STANDARDS_REPO_NAME")?,
        })
    }

    /// Returns the full `owner/name` reference for the standards repository.
    #[must_use]
    pub fn standards_repo_full(&self) -> String {
        format!("{}/{}", self.standards_repo_owner, self.standards_repo_name)
    }

    /// Exposes the GitHub private key for JWT signing.
    #[must_use]
    pub fn github_private_key_value(&self) -> &str {
        self.github_private_key.expose_secret()
    }

    /// Exposes the webhook secret for HMAC verification.
    #[must_use]
    pub fn webhook_secret_value(&self) -> &str {
        self.github_webhook_secret.expose_secret()
    }

    /// Exposes the database connection string.
    #[must_use]
    pub fn database_url_value(&self) -> &str {
        self.database_url.expose_secret()
    }

    /// Exposes the Anthropic API key.
    #[must_use]
    pub fn anthropic_api_key_value(&self) -> &str {
        self.anthropic_api_key.expose_secret()
    }

    /// Exposes the OIDC client secret.
    #[must_use]
    pub fn oidc_client_secret_value(&self) -> &str {
        self.oidc_client_secret.expose_secret()
    }
}

fn env_var(name: &str) -> Result<String> {
    std::env::var(name)
        .whatever_context(format!("missing required environment variable: {name}"))
}

fn parse_comma_list(name: &str) -> Vec<String> {
    std::env::var(name)
        .unwrap_or_default()
        .split(',')
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
        .collect()
}
