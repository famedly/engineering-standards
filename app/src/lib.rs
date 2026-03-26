//! Engineering Standards App — GitHub App that enforces engineering standards
//! across an organization's repositories via webhooks, AI code review, and
//! automated compliance PRs.

pub mod config;
pub mod dashboard;
pub mod db;
pub mod error;
pub mod github;
pub mod module;
pub mod modules;

mod static_regex;

use std::sync::Arc;

use axum::Router;
use snafu::ResultExt;
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::trace::TraceLayer;
use tower_sessions::cookie::time::Duration;
use tower_sessions::{Expiry, MemoryStore, SessionManagerLayer};
use tracing::Span;

use crate::config::Config;
use crate::error::Result;
use crate::module::{Context, Module};

/// Starts the application server.
pub async fn run() -> Result<()> {
	let _ = dotenvy::dotenv();

	let config = Config::from_env()?;

	tracing::info!(
		version = env!("CARGO_PKG_VERSION"),
		addr = %config.listen_addr,
		"starting engineering-standards-app",
	);

	let db = sqlx::PgPool::connect(config.database_url_value())
		.await
		.context(error::Database)?;

	sqlx::migrate!("./migrations")
		.run(&db)
		.await
		.context(error::Migration)?;

	let github_app = github::build_app_client(&config)?;

	// Build a single shared HTTP client with connection pooling.  This client is
	// reused for all outbound requests (OIDC token exchange, UserInfo calls) to
	// avoid re-establishing TCP connections on every authenticated request.
	let http_client = reqwest::Client::builder()
		.redirect(reqwest::redirect::Policy::none())
		.timeout(std::time::Duration::from_secs(10))
		.build()
		.whatever_context("building shared HTTP client")?;

	// Resolve OIDC provider metadata once at startup (caches Discovery doc +
	// UserInfo URL) so that login/callback handlers have zero extra round-trips.
	let (oidc_provider_metadata, userinfo_url) =
		dashboard::auth::discover_oidc_metadata(&config.oidc_issuer_url, &http_client)
			.await
			.whatever_context("OIDC discovery failed — check OIDC_ISSUER_URL")?;

	tracing::info!(url = %userinfo_url, "resolved OIDC userinfo endpoint");

	let modules: Vec<Arc<dyn Module>> = vec![
		modules::review::create(),
		modules::flake::create(),
		modules::pin::create(),
	];

	let listen_addr = config.listen_addr.clone();

	let context = Context {
		config: Arc::new(config),
		github_app: Arc::new(github_app),
		db,
		modules: Arc::new(modules),
		userinfo_url: Arc::new(userinfo_url),
		http_client: Arc::new(http_client),
		oidc_provider_metadata: Arc::new(oidc_provider_metadata),
	};

	let app = build_router(context);

	let listener = tokio::net::TcpListener::bind(&listen_addr)
		.await
		.context(error::ServerBind)?;

	tracing::info!(addr = %listen_addr, "listening");

	axum::serve(listener, app)
		.with_graceful_shutdown(shutdown_signal())
		.await
		.context(error::ServerStart)?;

	Ok(())
}

fn build_router(context: Context) -> Router {
	let mut app = Router::new()
		.route("/api/webhooks", axum::routing::post(module::webhook_handler))
		.route("/healthz", axum::routing::get(|| async { "ok" }))
		.merge(dashboard::routes(context.clone()));

	for module in context.modules.iter() {
		if let Some(routes) = module.routes() {
			app = app.merge(routes);
		}
	}

	let is_https = context.config.base_url.starts_with("https://");
	let session_store = MemoryStore::default();
	let session_layer = SessionManagerLayer::new(session_store)
		.with_secure(is_https)
		.with_http_only(true)
		.with_same_site(tower_sessions::cookie::SameSite::Lax)
		.with_expiry(Expiry::OnInactivity(Duration::hours(8)));

	let cors_origin: http::HeaderValue = context
		.config
		.base_url
		.parse()
		.unwrap_or_else(|_| panic!("BASE_URL is not a valid HTTP origin: {}", context.config.base_url));

	let cors = CorsLayer::new()
		.allow_origin(AllowOrigin::exact(cors_origin))
		.allow_methods([http::Method::GET, http::Method::POST])
		.allow_headers([http::header::CONTENT_TYPE, http::header::AUTHORIZATION]);

	let security_headers = axum::middleware::from_fn(add_security_headers);

	app.with_state(context)
		.layer(session_layer)
		.layer(security_headers)
		.layer(CatchPanicLayer::new())
		.layer(
			TraceLayer::new_for_http()
				.make_span_with(|request: &http::Request<_>| {
					let request_id = uuid::Uuid::new_v4().to_string();
					tracing::info_span!(
						"request",
						%request_id,
						method = %request.method(),
						uri = %request.uri(),
					)
				})
				.on_response(
					|response: &http::Response<_>, latency: std::time::Duration, _span: &Span| {
						tracing::info!(
							status = response.status().as_u16(),
							latency_ms = latency.as_millis(),
							"response"
						);
					},
				),
		)
		.layer(cors)
}

async fn add_security_headers(
	request: axum::extract::Request,
	next: axum::middleware::Next,
) -> axum::response::Response {
	let mut response = next.run(request).await;
	let headers = response.headers_mut();
	headers.insert(
		http::header::X_CONTENT_TYPE_OPTIONS,
		http::HeaderValue::from_static("nosniff"),
	);
	headers.insert(
		http::header::X_FRAME_OPTIONS,
		http::HeaderValue::from_static("DENY"),
	);
	headers.insert(
		http::header::REFERRER_POLICY,
		http::HeaderValue::from_static("strict-origin-when-cross-origin"),
	);
	headers.insert(
		http::header::CONTENT_SECURITY_POLICY,
		http::HeaderValue::from_static(
			"default-src 'self'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'",
		),
	);
	response
}

async fn shutdown_signal() {
	use tokio::signal;

	#[cfg(unix)]
	{
		match signal::unix::signal(signal::unix::SignalKind::terminate()) {
			Ok(mut sigterm) => {
				tokio::select! {
					() = async { signal::ctrl_c().await.ok(); } => {},
					_ = sigterm.recv() => {},
				}
			}
			Err(e) => {
				tracing::warn!(
					error = %e,
					"failed to install SIGTERM handler — shutdown via CTRL+C only",
				);
				signal::ctrl_c().await.ok();
			}
		}
	}

	#[cfg(not(unix))]
	{
		if let Err(e) = signal::ctrl_c().await {
			tracing::error!(error = %e, "failed to listen for CTRL+C");
		}
	}

	tracing::info!("shutdown signal received");
}
