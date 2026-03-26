//! Creates flake bump PRs and dispatches update events to consumer repos.

use snafu::ResultExt;

use crate::db;
use crate::error::{self, Result};
use crate::github::pr::PrBuilder;
use crate::module::Context;

const BUMP_BRANCH: &str = "engineering-standards/flake-bump";

/// Dispatches `repository_dispatch` events to all consumer repos that have a
/// flake integration, triggering their `update-engineering-standards` workflow.
///
/// Called when the engineering-standards repo pushes to main.
#[tracing::instrument(skip_all, name = "flake::dispatch_updates")]
pub async fn dispatch_updates_to_all(state: &Context) -> Result<()> {
	let repos = db::list_all_repos(&state.db).await?;
	let standards_full = state.config.standards_repo_full();

	let consumers: Vec<_> = repos
		.iter()
		.filter(|r| {
			r.repo_full_name != standards_full && r.flake_input_rev.is_some()
		})
		.collect();

	tracing::info!(
		count = consumers.len(),
		"dispatching update events to consumer repos",
	);

	let mut dispatched = 0usize;
	let mut errors = 0usize;

	let mut by_installation: std::collections::HashMap<i64, Vec<&db::RepoSyncStatus>> =
		std::collections::HashMap::new();
	for repo in &consumers {
		by_installation
			.entry(repo.installation_id)
			.or_default()
			.push(repo);
	}

	for (installation_id, installation_repos) in &by_installation {
		let github = match state.installation_client(*installation_id as u64).await {
			Ok(g) => g,
			Err(e) => {
				tracing::warn!(
					error = %e,
					%installation_id,
					"failed to get installation client for dispatch",
				);
				errors += installation_repos.len();
				continue;
			}
		};

		for repo in installation_repos {
			let Some((owner, name)) = repo.owner_and_name() else {
				continue;
			};

			match dispatch_repository_event(&github, owner, name).await {
				Ok(()) => {
					tracing::info!(repo = %repo.repo_full_name, "dispatched update event");
					dispatched += 1;
				}
				Err(e) => {
					tracing::warn!(
						repo = %repo.repo_full_name,
						error = %e,
						"failed to dispatch update event",
					);
					errors += 1;
				}
			}
		}
	}

	let _ = db::insert_audit_entry(
		&state.db,
		None,
		"dispatch_updates",
		"webhook",
		&serde_json::json!({ "dispatched": dispatched, "errors": errors }),
	)
	.await;

	tracing::info!(dispatched, errors, "dispatch complete");
	Ok(())
}

/// Sends a `repository_dispatch` event to a single repo.
///
/// The GitHub API returns 204 No Content on success, so we use `_post` to
/// get the raw response instead of trying to deserialize an empty body.
async fn dispatch_repository_event(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
) -> Result<()> {
	let response = github
		._post(
			format!("https://api.github.com/repos/{owner}/{repo}/dispatches"),
			Some(&serde_json::json!({
				"event_type": "engineering-standards-update",
			})),
		)
		.await
		.context(error::GitHub)?;

	let status = response.status();
	if !status.is_success() {
		snafu::whatever!("dispatch returned HTTP {status}");
	}

	Ok(())
}

/// Creates or updates a PR to bump the engineering-standards flake input.
///
/// Used as a fallback for repos that don't yet have the auto-update workflow.
#[tracing::instrument(skip_all, fields(%owner, %repo), name = "flake::create_bump_pr")]
pub async fn create_flake_bump_pr(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
	current_rev: &str,
	new_rev: &str,
) -> Result<()> {
	PrBuilder::new(github, owner, repo, BUMP_BRANCH)
		.commit_message(format!(
			"chore: bump engineering-standards flake input\n\n{current_rev} → {new_rev}"
		))
		.title("chore: bump engineering-standards flake input")
		.body(format!(
			"## Update engineering-standards\n\n\
			 The `engineering-standards` flake input is outdated.\n\n\
			 | | Revision |\n\
			 |---|---|\n\
			 | Current | `{current_rev}` |\n\
			 | New | `{new_rev}` |\n\n\
			 ### How to apply\n\n\
			 If your repo has the `update-engineering-standards` workflow, it will \
			 be triggered automatically. Otherwise, run locally:\n\n\
			 ```bash\n\
			 nix flake update engineering-standards\n\
			 nix run .#regenerateStandards\n\
			 ```\n\n\
			 > Created automatically by the engineering-standards GitHub App."
		))
		.execute()
		.await?;

	Ok(())
}
