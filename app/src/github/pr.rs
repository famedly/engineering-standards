//! Git tree API abstraction for creating PRs programmatically.

use snafu::ResultExt;

use crate::error::{self, Result};

/// A file to include in a PR commit.
pub struct PrFile {
	/// Repository-relative file path.
	pub path: String,
	/// UTF-8 file content.
	pub content: String,
}

/// Deletion of a file in a PR commit.
pub struct PrDeletion {
	/// Repository-relative path of the file to delete.
	pub path: String,
}

/// Builds and creates/updates a PR on a single branch.
pub struct PrBuilder<'a> {
	github: &'a octocrab::Octocrab,
	owner: &'a str,
	repo: &'a str,
	branch: &'a str,
	title: String,
	body: String,
	commit_message: String,
	files: Vec<PrFile>,
	deletions: Vec<PrDeletion>,
}

impl<'a> PrBuilder<'a> {
	/// Creates a new builder targeting the given branch.
	pub fn new(
		github: &'a octocrab::Octocrab,
		owner: &'a str,
		repo: &'a str,
		branch: &'a str,
	) -> Self {
		Self {
			github,
			owner,
			repo,
			branch,
			title: String::new(),
			body: String::new(),
			commit_message: String::new(),
			files: Vec::new(),
			deletions: Vec::new(),
		}
	}

	/// Sets the PR title.
	pub fn title(mut self, title: impl Into<String>) -> Self {
		self.title = title.into();
		self
	}

	/// Sets the PR body / description.
	pub fn body(mut self, body: impl Into<String>) -> Self {
		self.body = body.into();
		self
	}

	/// Sets the Git commit message.
	pub fn commit_message(mut self, msg: impl Into<String>) -> Self {
		self.commit_message = msg.into();
		self
	}

	/// Adds a single file to the commit.
	pub fn file(mut self, path: impl Into<String>, content: impl Into<String>) -> Self {
		self.files.push(PrFile {
			path: path.into(),
			content: content.into(),
		});
		self
	}

	/// Adds multiple files to the commit.
	pub fn files(mut self, files: impl IntoIterator<Item = PrFile>) -> Self {
		self.files.extend(files);
		self
	}

	/// Marks a file for deletion in the commit.
	pub fn deletion(mut self, path: impl Into<String>) -> Self {
		self.deletions.push(PrDeletion { path: path.into() });
		self
	}

	/// Marks multiple files for deletion.
	pub fn deletions(mut self, deletions: impl IntoIterator<Item = PrDeletion>) -> Self {
		self.deletions.extend(deletions);
		self
	}

	/// Execute: create blobs, tree, commit, push branch, open/update PR.
	///
	/// Returns `true` if a PR was created/updated, `false` if there were no
	/// tree items to commit.
	pub async fn execute(self) -> Result<bool> {
		let (owner, repo, branch) = (self.owner, self.repo, self.branch);

		let default_branch = self
			.github
			.repos(owner, repo)
			.get()
			.await
			.context(error::GitHub)?
			.default_branch
			.unwrap_or_else(|| "main".into());

		let base_sha = resolve_base_sha(self.github, owner, repo, &default_branch).await?;

		let mut tree_items: Vec<serde_json::Value> = Vec::new();

		for deletion in &self.deletions {
			tree_items.push(serde_json::json!({
				"path": deletion.path,
				"mode": "100644",
				"type": "blob",
				"sha": serde_json::Value::Null
			}));
		}

		for file in &self.files {
			let blob_sha = create_blob(self.github, owner, repo, &file.content).await?;
			tree_items.push(serde_json::json!({
				"path": file.path,
				"mode": "100644",
				"type": "blob",
				"sha": blob_sha
			}));
		}

		if tree_items.is_empty() {
			return Ok(false);
		}

		let tree_sha = create_tree(self.github, owner, repo, &base_sha, &tree_items).await?;
		let commit_sha =
			create_commit(self.github, owner, repo, &self.commit_message, &tree_sha, &base_sha)
				.await?;

		push_branch(self.github, owner, repo, branch, &commit_sha).await?;
		ensure_pr(
			self.github,
			owner,
			repo,
			branch,
			&default_branch,
			&self.title,
			&self.body,
		)
		.await?;

		Ok(true)
	}
}

// ── Low-level Git helpers ───────────────────────────────────────────────────

async fn resolve_base_sha(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
	default_branch: &str,
) -> Result<String> {
	let base_ref = github
		.repos(owner, repo)
		.get_ref(&octocrab::params::repos::Reference::Branch(
			default_branch.to_owned(),
		))
		.await
		.context(error::GitHub)?;

	match &base_ref.object {
		octocrab::models::repos::Object::Commit { sha, .. } => Ok(sha.clone()),
		_ => snafu::whatever!("unexpected git ref type"),
	}
}

async fn create_blob(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
	content: &str,
) -> Result<String> {
	let blob: serde_json::Value = github
		.post(
			format!("/repos/{owner}/{repo}/git/blobs"),
			Some(&serde_json::json!({ "content": content, "encoding": "utf-8" })),
		)
		.await
		.context(error::GitHub)?;

	extract_sha(&blob, "blob")
}

async fn create_tree(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
	base_sha: &str,
	items: &[serde_json::Value],
) -> Result<String> {
	let tree: serde_json::Value = github
		.post(
			format!("/repos/{owner}/{repo}/git/trees"),
			Some(&serde_json::json!({ "base_tree": base_sha, "tree": items })),
		)
		.await
		.context(error::GitHub)?;

	extract_sha(&tree, "tree")
}

async fn create_commit(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
	message: &str,
	tree_sha: &str,
	parent_sha: &str,
) -> Result<String> {
	let commit: serde_json::Value = github
		.post(
			format!("/repos/{owner}/{repo}/git/commits"),
			Some(&serde_json::json!({
				"message": message,
				"tree": tree_sha,
				"parents": [parent_sha]
			})),
		)
		.await
		.context(error::GitHub)?;

	extract_sha(&commit, "commit")
}

async fn push_branch(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
	branch: &str,
	commit_sha: &str,
) -> Result<()> {
	let ref_name = format!("refs/heads/{branch}");
	let create: std::result::Result<serde_json::Value, _> = github
		.post(
			format!("/repos/{owner}/{repo}/git/refs"),
			Some(&serde_json::json!({ "ref": ref_name, "sha": commit_sha })),
		)
		.await;

	if let Err(e) = create {
		tracing::debug!(
			error = %e,
			%branch,
			"branch ref already exists, force-updating",
		);
		let _: serde_json::Value = github
			.patch(
				format!("/repos/{owner}/{repo}/git/refs/heads/{branch}"),
				Some(&serde_json::json!({ "sha": commit_sha, "force": true })),
			)
			.await
			.context(error::GitHub)?;
	}

	Ok(())
}

async fn ensure_pr(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
	branch: &str,
	default_branch: &str,
	title: &str,
	body: &str,
) -> Result<()> {
	let existing = github
		.pulls(owner, repo)
		.list()
		.head(format!("{owner}:{branch}"))
		.state(octocrab::params::State::Open)
		.send()
		.await
		.context(error::GitHub)?;

	if existing.items.is_empty() {
		github
			.pulls(owner, repo)
			.create(title, branch, default_branch)
			.body(body)
			.send()
			.await
			.context(error::GitHub)?;
	}

	Ok(())
}

/// Fetches the recursive file tree for a given SHA via the Git Trees API.
pub async fn get_repo_tree(
	github: &octocrab::Octocrab,
	owner: &str,
	repo: &str,
	sha: &str,
) -> Result<std::collections::HashSet<String>> {
	let tree: serde_json::Value = github
		.get(
			format!("/repos/{owner}/{repo}/git/trees/{sha}?recursive=1"),
			None::<&()>,
		)
		.await
		.context(error::GitHub)?;

	Ok(tree
		.get("tree")
		.and_then(|t| t.as_array())
		.map(|items| {
			items
				.iter()
				.filter_map(|i| i.get("path")?.as_str().map(ToOwned::to_owned))
				.collect()
		})
		.unwrap_or_default())
}

fn extract_sha(value: &serde_json::Value, context: &str) -> Result<String> {
	value
		.get("sha")
		.and_then(|s| s.as_str())
		.map(ToOwned::to_owned)
		.ok_or_else(|| {
			error::BadRequest {
				message: format!("missing {context} sha from GitHub API"),
			}
			.build()
		})
}
