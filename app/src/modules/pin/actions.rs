//! GitHub Actions SHA pinning – scans workflows and resolves tags to commit SHAs.

use std::sync::LazyLock;

use regex::Regex;
use snafu::ResultExt;

use crate::error::{self, Result};
use crate::static_regex;

/// A GitHub Action reference using a mutable tag instead of a pinned SHA.
#[derive(Debug)]
pub struct UnpinnedAction {
    /// Workflow file path relative to the repo root.
    pub file_path: String,
    /// 1-based line number where the `uses:` directive was found.
    pub line_number: usize,
    /// Full trimmed line text.
    pub original: String,
    /// Action owner (e.g. `actions`).
    pub owner: String,
    /// Action repository (e.g. `checkout`).
    pub repo: String,
    /// Tag or branch reference (e.g. `v4`).
    pub reference: String,
    /// Resolved full-length commit SHA, if available.
    pub pinned_sha: Option<String>,
}

/// Scans all workflow files in a repo for actions using tags instead of SHAs.
///
/// Returns `(files_found, unpinned_actions)`. `files_found = 0` means the
/// `.github/workflows` directory does not exist or contains no YAML files.
#[tracing::instrument(skip_all, fields(%owner, %repo))]
pub async fn scan_repo_workflows(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
) -> Result<(usize, Vec<UnpinnedAction>)> {
    let content = github
        .repos(owner, repo)
        .get_content()
        .path(".github/workflows")
        .r#ref("HEAD")
        .send()
        .await;

    let workflow_files = match content {
        Ok(c) => c
            .items
            .iter()
            .filter(|i| i.path.ends_with(".yml") || i.path.ends_with(".yaml"))
            .map(|i| i.path.clone())
            .collect::<Vec<_>>(),
        Err(_) => return Ok((0, vec![])),
    };

    let files_found = workflow_files.len();

    let mut findings = Vec::new();

    for path in &workflow_files {
        let Ok(file_content) = fetch_file(github, owner, repo, path).await else {
            continue;
        };

        let mut file_findings = scan_workflow_content(path, &file_content);

        for finding in &mut file_findings {
            if finding.pinned_sha.is_none() {
                finding.pinned_sha =
                    resolve_tag_to_sha(github, &finding.owner, &finding.repo, &finding.reference)
                        .await
                        .ok();
            }
        }

        findings.extend(file_findings);
    }

    Ok((files_found, findings))
}

/// Fast check: counts unpinned actions without resolving SHAs.
///
/// Returns `(files_found, unpinned_count)`. Much faster than
/// `scan_repo_workflows` because it skips the per-action GitHub API calls.
#[tracing::instrument(skip_all, fields(%owner, %repo))]
pub async fn count_unpinned(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
) -> Result<(usize, usize)> {
    let content = github
        .repos(owner, repo)
        .get_content()
        .path(".github/workflows")
        .r#ref("HEAD")
        .send()
        .await;

    let workflow_files = match content {
        Ok(c) => c
            .items
            .iter()
            .filter(|i| i.path.ends_with(".yml") || i.path.ends_with(".yaml"))
            .map(|i| i.path.clone())
            .collect::<Vec<_>>(),
        Err(_) => return Ok((0, 0)),
    };

    let files_found = workflow_files.len();
    let mut unpinned_count = 0;

    for path in &workflow_files {
        if let Ok(c) = fetch_file(github, owner, repo, path).await {
            unpinned_count += scan_workflow_content(path, &c).len();
        }
    }

    Ok((files_found, unpinned_count))
}

static USES_RE: LazyLock<Regex> =
    LazyLock::new(|| static_regex::compile(r"uses:\s*([^/]+)/([^@]+)@(.+)"));
static SHA_RE: LazyLock<Regex> = LazyLock::new(|| static_regex::compile(r"^[0-9a-f]{40}$"));

fn scan_workflow_content(path: &str, content: &str) -> Vec<UnpinnedAction> {
    content
        .lines()
        .enumerate()
        .filter_map(|(i, line)| {
            let trimmed = line.trim();
            let caps = USES_RE.captures(trimmed)?;
            let reference = caps[3].trim().to_owned();

            if SHA_RE.is_match(&reference) {
                return None;
            }

            Some(UnpinnedAction {
                file_path: path.to_owned(),
                line_number: i + 1,
                original: trimmed.to_owned(),
                owner: caps[1].to_string(),
                repo: caps[2].to_string(),
                reference,
                pinned_sha: None,
            })
        })
        .collect()
}

async fn resolve_tag_to_sha(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    tag: &str,
) -> Result<String> {
    let r#ref = github
        .repos(owner, repo)
        .get_ref(&octocrab::params::repos::Reference::Tag(tag.to_owned()))
        .await
        .context(error::GitHub)?;

    match &r#ref.object {
        octocrab::models::repos::Object::Commit { sha, .. } => Ok(sha.clone()),
        _ => snafu::whatever!("tag {tag} is not a commit"),
    }
}

/// Creates a PR that pins all unpinned actions to their full SHA.
#[tracing::instrument(skip_all, fields(%owner, %repo))]
pub async fn create_pin_pr(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    findings: &[UnpinnedAction],
) -> Result<()> {
    use crate::github::pr::{PrBuilder, PrFile};

    let files_to_update = collect_file_updates(github, owner, repo, findings).await?;
    if files_to_update.is_empty() {
        return Ok(());
    }

    let pr_files = files_to_update
        .into_iter()
        .map(|(path, content)| PrFile { path, content });

    PrBuilder::new(github, owner, repo, "chore/pin-github-actions")
        .commit_message("chore: pin GitHub Actions to full-length commit SHAs")
        .title("chore: pin GitHub Actions to full-length commit SHAs")
        .body(format!(
            "Pins {} action reference(s) to full-length commit SHAs for supply-chain security.",
            findings.len(),
        ))
        .files(pr_files)
        .execute()
        .await?;

    Ok(())
}

async fn collect_file_updates(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    findings: &[UnpinnedAction],
) -> Result<Vec<(String, String)>> {
    let mut updates = Vec::new();
    let mut seen_paths = std::collections::HashSet::new();

    for finding in findings {
        if !seen_paths.insert(finding.file_path.clone()) {
            continue;
        }

        let mut content = fetch_file(github, owner, repo, &finding.file_path).await?;

        for f in findings.iter().filter(|f| f.file_path == finding.file_path) {
            if let Some(sha) = &f.pinned_sha {
                let old = format!("{}@{}", f.repo, f.reference);
                let new = format!("{}@{} # {}", f.repo, sha, f.reference);
                content = content.replace(&old, &new);
            }
        }

        updates.push((finding.file_path.clone(), content));
    }

    Ok(updates)
}

async fn fetch_file(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    path: &str,
) -> Result<String> {
    crate::github::fetch_file_content(github, owner, repo, path, "HEAD").await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_unpinned_action() {
        let content = "    - uses: actions/checkout@v4\n";
        let findings = scan_workflow_content(".github/workflows/ci.yml", content);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].owner, "actions");
        assert_eq!(findings[0].repo, "checkout");
        assert_eq!(findings[0].reference, "v4");
    }

    #[test]
    fn ignores_sha_pinned_action() {
        let content = "    - uses: actions/checkout@a5ac7e51b41094c92402da3b24376905380afc29\n";
        let findings = scan_workflow_content("ci.yml", content);
        assert!(findings.is_empty());
    }

    #[test]
    fn detects_composite_action_path() {
        let content = "    - uses: actions/cache/restore@v4\n";
        let findings = scan_workflow_content("ci.yml", content);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].repo, "cache/restore");
    }

    #[test]
    fn multiple_actions_per_file() {
        let content = "\
            - uses: actions/checkout@v4\n\
            - run: echo hello\n\
            - uses: actions/setup-node@v3\n";
        let findings = scan_workflow_content("ci.yml", content);
        assert_eq!(findings.len(), 2);
    }

    #[test]
    fn line_numbers_are_one_based() {
        let content = "line 1\nline 2\n    - uses: actions/checkout@v4\n";
        let findings = scan_workflow_content("ci.yml", content);
        assert_eq!(findings[0].line_number, 3);
    }

    #[test]
    fn no_uses_returns_empty() {
        let content = "name: CI\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n";
        let findings = scan_workflow_content("ci.yml", content);
        assert!(findings.is_empty());
    }
}
