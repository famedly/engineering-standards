//! Nix flake compliance tracking and automated bump PRs.

pub mod detector;
pub mod updater;

pub use detector::{get_standards_head, scan_repo_compliance};

use std::sync::Arc;

use crate::error::Result;
use crate::module::{Module, WebhookContext};

struct FlakeModule;

#[async_trait::async_trait]
impl Module for FlakeModule {
	fn name(&self) -> &'static str {
		"flake"
	}

	async fn handle_webhook(&self, ctx: &WebhookContext) -> Result<bool> {
		let action = ctx.action.as_deref();

		match (ctx.event.as_str(), action) {
			("push", _) => {
				let r#ref = ctx
					.payload
					.get("ref")
					.and_then(|r| r.as_str())
					.unwrap_or("");
				if r#ref == "refs/heads/main" {
					let repo_full = ctx.repo_full_name().unwrap_or_default();
					let standards_full = ctx.state.config.standards_repo_full();

					if repo_full == standards_full {
						tracing::info!("engineering-standards pushed to main — dispatching updates to all consumer repos");
						if let Err(e) = updater::dispatch_updates_to_all(&ctx.state).await {
							tracing::error!(error = %e, "failed to dispatch updates");
						}
					} else if let Err(e) = detector::on_push(ctx).await {
						tracing::debug!(error = %e, "flake lock detection skipped");
					}
				}
			}
			("installation", Some("created"))
			| ("installation_repositories", Some("added")) => {
				if let Err(e) = detector::on_installation(ctx).await {
					tracing::debug!(error = %e, "initial flake lock read skipped");
				}
			}
			_ => {}
		}

		Ok(false)
	}
}

/// Tracks `flake.lock` state and auto-creates bump PRs on push.
pub fn create() -> Arc<dyn Module> {
	Arc::new(FlakeModule)
}
