//! Module system: trait-based webhook dispatch and shared application context.

use std::sync::Arc;

use axum::extract::State;
use axum::http::HeaderMap;
use axum::response::IntoResponse;
use axum::{body::Bytes, Router};
use snafu::ResultExt;

use crate::config::Config;
use crate::error::{self, Result};
use crate::github;

/// Shared application state available to all handlers and modules.
#[derive(Clone)]
pub struct Context {
	/// Resolved once at startup, immutable at runtime.
	pub config: Arc<Config>,
	/// Authenticated as the GitHub App itself (not an installation).
	pub github_app: Arc<octocrab::Octocrab>,
	/// Postgres connection pool with automatic reconnects.
	pub db: sqlx::PgPool,
	/// Dynamically dispatched feature modules (review, pin, flake).
	pub modules: Arc<Vec<Arc<dyn Module>>>,
	/// OIDC `UserInfo` endpoint URL, resolved once at startup via discovery.
	pub userinfo_url: Arc<String>,
	/// Shared HTTP client with a persistent connection pool. Reused for all
	/// outbound requests (`UserInfo`, OIDC token exchange) to avoid reconnect
	/// overhead on every authenticated request.
	pub http_client: Arc<reqwest::Client>,
	/// OIDC provider metadata resolved once at startup. Avoids a discovery
	/// round-trip to the `IdP` on every login and callback request.
	pub oidc_provider_metadata: Arc<openidconnect::core::CoreProviderMetadata>,
}

impl Context {
	/// Returns an installation-scoped GitHub API client.
	#[tracing::instrument(skip_all, fields(%installation_id))]
	pub async fn installation_client(
		&self,
		installation_id: u64,
	) -> Result<octocrab::Octocrab> {
		github::installation_client(&self.github_app, installation_id).await
	}
}

/// Webhook event context passed to module handlers.
pub struct WebhookContext {
	/// GitHub delivery ID for deduplication/tracing.
	pub delivery_id: String,
	/// Event type (e.g. `push`, `pull_request`).
	pub event: String,
	/// Event action (e.g. `opened`, `synchronize`).
	pub action: Option<String>,
	/// GitHub App installation ID for this event.
	pub installation_id: u64,
	/// Raw JSON webhook payload.
	pub payload: serde_json::Value,
	/// Shared application state.
	pub state: Context,
}

impl WebhookContext {
	/// Returns an installation-scoped GitHub client for this webhook.
	pub async fn github(&self) -> Result<octocrab::Octocrab> {
		self.state.installation_client(self.installation_id).await
	}

	/// Extracts the full repository name from the payload.
	#[must_use]
	pub fn repo_full_name(&self) -> Option<String> {
		github::extract_repo_full_name(&self.payload)
	}
}

/// Trait implemented by each feature module (review, flake, pin, …).
///
/// Uses `async_trait` because we need `Arc<dyn Module>` for dynamic dispatch.
#[async_trait::async_trait]
pub trait Module: Send + Sync + 'static {
	/// Returns the module's unique name for logging and diagnostics.
	fn name(&self) -> &'static str;

	/// Returns additional Axum routes provided by this module, if any.
	fn routes(&self) -> Option<Router<Context>> {
		None
	}

	/// Handles an incoming webhook event; returns `true` if the module acted on it.
	async fn handle_webhook(&self, _ctx: &WebhookContext) -> Result<bool> {
		Ok(false)
	}
}

/// Webhook ingestion endpoint: verifies signature, parses event, dispatches.
#[tracing::instrument(skip_all, name = "webhook_handler")]
pub async fn webhook_handler(
	State(state): State<Context>,
	headers: HeaderMap,
	body: Bytes,
) -> Result<impl IntoResponse> {
	let signature = headers
		.get("x-hub-signature-256")
		.and_then(|v| v.to_str().ok())
		.ok_or(error::WebhookSignature.build())?;

	github::verify_webhook_signature(state.config.webhook_secret_value(), signature, &body)?;

	let delivery_id = headers
		.get("x-github-delivery")
		.and_then(|v| v.to_str().ok())
		.unwrap_or("unknown").to_owned();

	let event = headers
		.get("x-github-event")
		.and_then(|v| v.to_str().ok())
		.unwrap_or("unknown").to_owned();

	let payload: serde_json::Value =
		serde_json::from_slice(&body).context(error::Serialization)?;

	let action = payload
		.get("action")
		.and_then(|a| a.as_str())
		.map(String::from);

	let installation_id = github::extract_installation_id(&payload).ok_or_else(|| {
		error::BadRequest {
			message: "missing installation.id in webhook payload".to_owned(),
		}
		.build()
	})?;

	tracing::info!(
		%delivery_id, %event, ?action, %installation_id,
		"webhook received"
	);

	let ctx = WebhookContext {
		delivery_id,
		event,
		action,
		installation_id,
		payload,
		state: state.clone(),
	};

	for module in state.modules.iter() {
		if let Err(e) = module.handle_webhook(&ctx).await {
			tracing::error!(
				module = module.name(),
				error = %e,
				"module webhook handler failed"
			);
		}
	}

	Ok(axum::Json(serde_json::json!({ "ok": true })))
}
