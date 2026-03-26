//! Application error types following the snafu + `SpanTrace` pattern.

use axum::{Json, http::StatusCode, response::IntoResponse};
use snafu::{Report, Snafu};
use std::fmt;
use tracing_error::SpanTrace;

/// Captures span trace context at error creation site for request correlation.
#[derive(Debug, Clone)]
pub struct SpanTraceWrapper(SpanTrace);

impl snafu::GenerateImplicitData for SpanTraceWrapper {
    fn generate() -> Self {
        Self(SpanTrace::capture())
    }
}

impl SpanTraceWrapper {
    /// Extracts the `request_id` from the captured span trace by looking for
    /// the `request` span's `request_id` field in the formatted span string.
    fn request_id(&self) -> Option<String> {
        let mut request_id: Option<String> = None;
        self.0.with_spans(|meta, formatted| {
            if meta.name() == "request" {
                for part in formatted.split_whitespace() {
                    if let Some(id) = part.strip_prefix("request_id=") {
                        request_id = Some(id.to_owned());
                        return false;
                    }
                }
            }
            true
        });
        request_id
    }
}

impl fmt::Display for SpanTraceWrapper {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.0.status() == tracing_error::SpanTraceStatus::CAPTURED {
            writeln!(f, "\nAt:")?;
            self.0.fmt(f)?;
            writeln!(f)?;
        }
        Ok(())
    }
}

/// Top-level application error with span trace context on every variant.
#[derive(Debug, Snafu)]
#[snafu(visibility(pub), context(suffix(false)))]
#[allow(missing_docs)]
pub enum Error {
    #[snafu(display("Database error"))]
    Database {
        source: sqlx::Error,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("Database migration error"))]
    Migration {
        source: sqlx::migrate::MigrateError,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("GitHub API error"))]
    GitHub {
        #[snafu(source(from(octocrab::Error, Box::new)))]
        source: Box<octocrab::Error>,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("HTTP client error"))]
    HttpClient {
        source: reqwest::Error,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("JSON serialization error"))]
    Serialization {
        source: serde_json::Error,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("Server bind error"))]
    ServerBind {
        source: std::io::Error,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("Server start error"))]
    ServerStart {
        source: std::io::Error,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("Webhook signature mismatch"))]
    WebhookSignature {
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("Not found"))]
    NotFound {
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("Unauthorized"))]
    Unauthorized {
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("Bad request: {message}"))]
    BadRequest {
        message: String,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(display("OIDC error: {message}"))]
    Oidc {
        message: String,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },

    #[snafu(whatever, display("{message}"))]
    Whatever {
        message: String,
        #[snafu(source(from(Box<dyn std::error::Error + Send + Sync>, Some)))]
        source: Option<Box<dyn std::error::Error + Send + Sync>>,
        #[snafu(implicit)]
        context: SpanTraceWrapper,
    },
}

/// Convenience alias used throughout the crate.
pub type Result<T, E = Error> = std::result::Result<T, E>;

impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        let (status_code, message) = match &self {
            Error::Database { .. } => (StatusCode::INTERNAL_SERVER_ERROR, "Database error"),
            Error::Migration { .. } => (StatusCode::INTERNAL_SERVER_ERROR, "Migration error"),
            Error::GitHub { .. } => (StatusCode::BAD_GATEWAY, "GitHub API error"),
            Error::HttpClient { .. } => (StatusCode::BAD_GATEWAY, "HTTP client error"),
            Error::Serialization { .. } => {
                (StatusCode::INTERNAL_SERVER_ERROR, "Serialization error")
            }
            Error::ServerBind { .. } => (StatusCode::INTERNAL_SERVER_ERROR, "Server bind error"),
            Error::ServerStart { .. } => (StatusCode::INTERNAL_SERVER_ERROR, "Server start error"),
            Error::WebhookSignature { .. } => (StatusCode::UNAUTHORIZED, "Webhook signature mismatch"),
            Error::NotFound { .. } => (StatusCode::NOT_FOUND, "Not found"),
            Error::Unauthorized { .. } => (StatusCode::UNAUTHORIZED, "Unauthorized"),
            Error::BadRequest { .. } => (StatusCode::BAD_REQUEST, "Bad request"),
            Error::Oidc { .. } => (StatusCode::INTERNAL_SERVER_ERROR, "Authentication error"),
            Error::Whatever { .. } => (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error"),
        };

        let ctx = self.context().clone();
        let request_id = ctx.request_id();

        let body = Json(serde_json::json!({
            "error": message,
            "request_id": request_id,
        }));

        tracing::error!("{}{ctx}", Report::from_error(self));

        (status_code, body).into_response()
    }
}

impl Error {
    /// Returns the span trace context attached to this error.
    #[must_use]
    pub fn context(&self) -> &SpanTraceWrapper {
        match self {
            Error::Database { context, .. }
            | Error::Migration { context, .. }
            | Error::GitHub { context, .. }
            | Error::HttpClient { context, .. }
            | Error::Serialization { context, .. }
            | Error::ServerBind { context, .. }
            | Error::ServerStart { context, .. }
            | Error::WebhookSignature { context, .. }
            | Error::NotFound { context, .. }
            | Error::Unauthorized { context, .. }
            | Error::BadRequest { context, .. }
            | Error::Oidc { context, .. }
            | Error::Whatever { context, .. } => context,
        }
    }
}
