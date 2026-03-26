//! GitHub App authentication, webhook verification, and Git API utilities.

pub mod pr;

use hmac::{Hmac, Mac};
use sha2::Sha256;
use snafu::ResultExt;

use secrecy::{ExposeSecret, SecretString};

use crate::config::Config;
use crate::error::{self, Result};

type HmacSha256 = Hmac<Sha256>;

/// Creates an app-level Octocrab instance authenticated as the GitHub App.
#[tracing::instrument(skip_all, name = "github::build_app_client")]
pub fn build_app_client(config: &Config) -> Result<octocrab::Octocrab> {
    let key = jsonwebtoken::EncodingKey::from_rsa_pem(
        config.github_private_key_value().as_bytes(),
    )
    .whatever_context("parsing GitHub App private key")?;

    octocrab::Octocrab::builder()
        .app(config.github_app_id.into(), key)
        .build()
        .whatever_context("building GitHub App client")
}

/// Returns an installation-scoped Octocrab client.
#[tracing::instrument(skip_all, fields(%installation_id))]
pub async fn installation_client(
    app_client: &octocrab::Octocrab,
    installation_id: u64,
) -> Result<octocrab::Octocrab> {
    let (client, _token) = app_client
        .installation_and_token(installation_id.into())
        .await
        .context(error::GitHub)?;

    Ok(client)
}

/// Returns an installation-scoped Octocrab client together with its bearer
/// token (needed for raw HTTP requests that require custom Accept headers).
#[tracing::instrument(skip_all, fields(%installation_id))]
pub async fn installation_client_with_token(
    app_client: &octocrab::Octocrab,
    installation_id: u64,
) -> Result<(octocrab::Octocrab, SecretString)> {
    let (client, token) = app_client
        .installation_and_token(installation_id.into())
        .await
        .context(error::GitHub)?;

    Ok((client, SecretString::from(token.expose_secret().to_owned())))
}

/// Verifies the HMAC-SHA256 signature of a GitHub webhook payload.
pub fn verify_webhook_signature(
    secret: &str,
    signature_header: &str,
    body: &[u8],
) -> Result<()> {
    let expected = signature_header
        .strip_prefix("sha256=")
        .ok_or(error::WebhookSignature.build())?;

    let expected_bytes =
        hex::decode(expected).map_err(|_| error::WebhookSignature.build())?;

    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .whatever_context("invalid HMAC key length")?;
    mac.update(body);

    mac.verify_slice(&expected_bytes)
        .map_err(|_| error::WebhookSignature.build())
}

/// Extracts the installation ID from a webhook payload.
#[must_use]
pub fn extract_installation_id(payload: &serde_json::Value) -> Option<u64> {
    payload
        .get("installation")?
        .get("id")?
        .as_u64()
}

/// Extracts the full repository name (owner/repo) from a webhook payload.
#[must_use]
pub fn extract_repo_full_name(payload: &serde_json::Value) -> Option<String> {
    payload
        .get("repository")?
        .get("full_name")?
        .as_str()
        .map(String::from)
}

/// Fetches and decodes a single file from a GitHub repository.
///
/// Uses the Contents API with `HEAD` ref. Returns the decoded text content.
pub async fn fetch_file_content(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    path: &str,
    git_ref: &str,
) -> Result<String> {
    let content = github
        .repos(owner, repo)
        .get_content()
        .path(path)
        .r#ref(git_ref)
        .send()
        .await
        .context(error::GitHub)?;

    content
        .items
        .first()
        .ok_or_else(|| error::NotFound.build())?
        .decoded_content()
        .ok_or_else(|| {
            error::BadRequest {
                message: format!("unable to decode content of {path}"),
            }
            .build()
        })
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn valid_webhook_signature() {
        let secret = "test-secret";
        let body = b"payload body";
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
        mac.update(body);
        let sig = hex::encode(mac.finalize().into_bytes());
        let header = format!("sha256={sig}");

        assert!(verify_webhook_signature(secret, &header, body).is_ok());
    }

    #[test]
    fn invalid_webhook_signature() {
        assert!(verify_webhook_signature("secret", "sha256=0000", b"body").is_err());
    }

    #[test]
    fn missing_sha256_prefix() {
        assert!(verify_webhook_signature("secret", "md5=abc", b"body").is_err());
    }

    #[test]
    fn extracts_installation_id() {
        let payload = serde_json::json!({"installation": {"id": 42}});
        assert_eq!(extract_installation_id(&payload), Some(42));
    }

    #[test]
    fn missing_installation_id() {
        let payload = serde_json::json!({"other": "data"});
        assert_eq!(extract_installation_id(&payload), None);
    }

    #[test]
    fn extracts_repo_full_name() {
        let payload = serde_json::json!({"repository": {"full_name": "org/repo"}});
        assert_eq!(extract_repo_full_name(&payload), Some("org/repo".into()));
    }
}
