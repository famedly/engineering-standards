//! Entry point – minimal bootstrap only.

use tracing_subscriber::{prelude::*, EnvFilter};

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| {
                EnvFilter::new("engineering_standards_app=info,tower_http=info")
            }),
        )
        .with(tracing_subscriber::fmt::layer().json())
        .with(tracing_error::ErrorLayer::default())
        .init();

    if let Err(e) = engineering_standards_app::run().await {
        tracing::error!("{e}");
        std::process::exit(1);
    }
}
