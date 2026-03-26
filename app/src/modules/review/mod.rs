//! AI-powered code review module using Anthropic Claude.

mod claude;
mod formatter;
mod handler;

use std::sync::Arc;

use crate::error::Result;
use crate::module::{Module, WebhookContext};

struct ReviewModule;

#[async_trait::async_trait]
impl Module for ReviewModule {
	fn name(&self) -> &'static str {
		"review"
	}

	async fn handle_webhook(&self, ctx: &WebhookContext) -> Result<bool> {
		match (ctx.event.as_str(), ctx.action.as_deref()) {
			("pull_request", Some("opened" | "synchronize")) => {
				handler::on_pull_request(ctx).await?;
				Ok(true)
			}
			("issue_comment", Some("created")) => {
				if handler::is_review_trigger(&ctx.payload) {
					handler::on_review_comment(ctx).await?;
					Ok(true)
				} else {
					Ok(false)
				}
			}
			_ => Ok(false),
		}
	}
}

/// Registers PR-event triggers for AI-powered code review.
pub fn create() -> Arc<dyn Module> {
	Arc::new(ReviewModule)
}
