//! Docker image digest pinning – scans Dockerfiles and resolves tags to SHA256 digests.

use std::sync::LazyLock;

use regex::Regex;
use snafu::ResultExt;

use crate::error::{self, Result};
use crate::static_regex;

/// A Docker image reference using a mutable tag instead of a SHA256 digest.
#[derive(Debug)]
pub struct UnpinnedImage {
    /// File path relative to the repo root.
    pub file_path: String,
    /// 1-based line number.
    pub line_number: usize,
    /// Image name (e.g. `postgres`, `ghcr.io/org/image`).
    pub image: String,
    /// Image tag (e.g. `16-alpine`, `latest`).
    pub tag: String,
    /// Resolved SHA256 digest, if available.
    pub digest: Option<String>,
}

/// Scans Dockerfiles and docker-compose files for unpinned image references.
///
/// Returns `(files_found, unpinned_images)`. `files_found = 0` means no
/// Dockerfiles or docker-compose files were found in the repository root.
#[tracing::instrument(skip_all, fields(%owner, %repo))]
pub async fn scan_repo_dockerfiles(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
) -> Result<(usize, Vec<UnpinnedImage>)> {
    let content = github.repos(owner, repo).get_content().path("").r#ref("HEAD").send().await;
    let all_files: Vec<String> = match content {
        Ok(c) => c.items.iter().map(|i| i.path.clone()).collect(),
        Err(_) => return Ok((0, vec![])),
    };

    let docker_files: Vec<&String> = all_files
        .iter()
        .filter(|f| f.contains("Dockerfile") || f.contains("docker-compose") || f.ends_with(".dockerfile"))
        .collect();

    let files_found = docker_files.len();
    let mut findings = Vec::new();

    for path in docker_files {
        let Ok(file_content) = fetch_file(github, owner, repo, path).await else {
            continue;
        };

        let mut file_findings = if path.contains("Dockerfile") || path.ends_with(".dockerfile") {
            scan_dockerfile(path, &file_content)
        } else {
            scan_compose_file(path, &file_content)
        };

        for finding in &mut file_findings {
            if finding.digest.is_none() {
                finding.digest = resolve_digest(&finding.image, &finding.tag).await.ok();
            }
        }

        findings.extend(file_findings);
    }

    Ok((files_found, findings))
}

/// Fast check: counts unpinned images without resolving digests.
///
/// Returns `(files_found, unpinned_count)`. Skips the Docker Hub API calls.
#[tracing::instrument(skip_all, fields(%owner, %repo))]
pub async fn count_unpinned(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
) -> Result<(usize, usize)> {
    let content = github.repos(owner, repo).get_content().path("").r#ref("HEAD").send().await;
    let all_files: Vec<String> = match content {
        Ok(c) => c.items.iter().map(|i| i.path.clone()).collect(),
        Err(_) => return Ok((0, 0)),
    };

    let docker_files: Vec<&String> = all_files
        .iter()
        .filter(|f| f.contains("Dockerfile") || f.contains("docker-compose") || f.ends_with(".dockerfile"))
        .collect();

    let files_found = docker_files.len();
    let mut unpinned_count = 0;

    for path in &docker_files {
        if let Ok(c) = fetch_file(github, owner, repo, path).await {
            let findings = if path.contains("Dockerfile") || path.ends_with(".dockerfile") {
                scan_dockerfile(path, &c)
            } else {
                scan_compose_file(path, &c)
            };
            unpinned_count += findings.len();
        }
    }

    Ok((files_found, unpinned_count))
}

static FROM_RE: LazyLock<Regex> =
    LazyLock::new(|| static_regex::compile(r"(?i)^FROM\s+(\S+?)(?::(\S+?))?(?:\s|$)"));
static IMAGE_RE: LazyLock<Regex> =
    LazyLock::new(|| static_regex::compile(r#"image:\s*['"]?(\S+?)['"]?\s*$"#));

fn scan_dockerfile(path: &str, content: &str) -> Vec<UnpinnedImage> {
    content
        .lines()
        .enumerate()
        .filter_map(|(i, line)| {
            let caps = FROM_RE.captures(line.trim())?;
            let image = caps.get(1)?.as_str().to_owned();
            let tag = caps
                .get(2).map_or_else(|| "latest".into(), |m| m.as_str().to_owned());

            if tag.contains("@sha256:") || image == "scratch" {
                return None;
            }

            Some(UnpinnedImage {
                file_path: path.into(),
                line_number: i + 1,
                image,
                tag,
                digest: None,
            })
        })
        .collect()
}

fn scan_compose_file(path: &str, content: &str) -> Vec<UnpinnedImage> {
    content
        .lines()
        .enumerate()
        .filter_map(|(i, line)| {
            let caps = IMAGE_RE.captures(line.trim())?;
            let full = caps.get(1)?.as_str();

            if full.contains("@sha256:") {
                return None;
            }

            let (image, tag) = if let Some((img, t)) = full.rsplit_once(':') {
                (img.to_owned(), t.to_owned())
            } else {
                (full.to_owned(), "latest".into())
            };

            Some(UnpinnedImage {
                file_path: path.into(),
                line_number: i + 1,
                image,
                tag,
                digest: None,
            })
        })
        .collect()
}

static REGISTRY_CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new())
});

#[tracing::instrument(skip_all, fields(%image, %tag))]
async fn resolve_digest(image: &str, tag: &str) -> Result<String> {
    let library_image = format!("library/{image}");
    let (registry, repository): (&str, &str) = if image.contains('.') {
        let parts: Vec<&str> = image.splitn(2, '/').collect();
        (parts[0], *parts.get(1).unwrap_or(&image))
    } else if image.contains('/') {
        ("registry-1.docker.io", image)
    } else {
        ("registry-1.docker.io", &library_image)
    };

    let is_docker_hub = registry == "registry-1.docker.io";
    let manifest_url = format!("https://{registry}/v2/{repository}/manifests/{tag}");

    let mut request = REGISTRY_CLIENT
        .head(&manifest_url)
        .header("Accept", "application/vnd.docker.distribution.manifest.v2+json");

    if is_docker_hub {
        let token_url = format!(
            "https://auth.docker.io/token?service=registry.docker.io&scope=repository:{repository}:pull"
        );
        let token_resp: serde_json::Value = REGISTRY_CLIENT
            .get(&token_url)
            .send()
            .await
            .context(error::HttpClient)?
            .json()
            .await
            .context(error::HttpClient)?;
        let token = token_resp
            .get("token")
            .and_then(|t| t.as_str())
            .ok_or_else(|| {
                error::BadRequest { message: "missing Docker auth token".to_owned() }.build()
            })?;
        request = request.header("Authorization", format!("Bearer {token}"));
    }

    let resp = request.send().await.context(error::HttpClient)?;

    if resp.status() == reqwest::StatusCode::UNAUTHORIZED {
        snafu::whatever!(
            "registry {registry} requires authentication — cannot resolve digest for {image}:{tag}"
        );
    }

    resp.headers()
        .get("docker-content-digest")
        .and_then(|v| v.to_str().ok())
        .map(ToOwned::to_owned)
        .ok_or_else(|| error::BadRequest { message: "missing Docker digest header".to_owned() }.build())
}

/// Creates a PR that pins all unpinned Docker images to their digest.
#[tracing::instrument(skip_all, fields(%owner, %repo))]
pub async fn create_pin_pr(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    findings: &[UnpinnedImage],
) -> Result<()> {
    use crate::github::pr::{PrBuilder, PrFile};

    let file_updates = collect_file_updates(github, owner, repo, findings).await?;
    if file_updates.is_empty() {
        return Ok(());
    }

    let pr_files = file_updates
        .into_iter()
        .map(|(path, content)| PrFile { path, content });

    PrBuilder::new(github, owner, repo, "chore/pin-docker-digests")
        .commit_message("chore: pin Docker images to SHA256 digests")
        .title("chore: pin Docker images to SHA256 digests")
        .body(format!(
            "Pins {} Docker image reference(s) to SHA256 digests for supply-chain security.",
            findings.len(),
        ))
        .files(pr_files)
        .execute()
        .await?;

    Ok(())
}

/// Collects updated file contents with digests applied.
async fn collect_file_updates(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
    findings: &[UnpinnedImage],
) -> Result<Vec<(String, String)>> {
    let mut updates = Vec::new();
    let mut seen_paths = std::collections::HashSet::new();

    for finding in findings {
        if !seen_paths.insert(finding.file_path.clone()) {
            continue;
        }

        let mut content = fetch_file(github, owner, repo, &finding.file_path).await?;
        for f in findings.iter().filter(|f| f.file_path == finding.file_path) {
            if let Some(digest) = &f.digest {
                let old = format!("{}:{}", f.image, f.tag);
                let new = format!("{}:{}@{}", f.image, f.tag, digest);
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
    fn detects_unpinned_from_instruction() {
        let content = "FROM postgres:16-alpine\nRUN echo hello\n";
        let findings = scan_dockerfile("Dockerfile", content);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].image, "postgres");
        assert_eq!(findings[0].tag, "16-alpine");
    }

    #[test]
    fn ignores_digest_pinned_image() {
        let content = "FROM postgres:16@sha256:abc123\n";
        let findings = scan_dockerfile("Dockerfile", content);
        assert!(findings.is_empty());
    }

    #[test]
    fn ignores_scratch_base() {
        let content = "FROM scratch\n";
        let findings = scan_dockerfile("Dockerfile", content);
        assert!(findings.is_empty());
    }

    #[test]
    fn defaults_to_latest_tag() {
        let content = "FROM ubuntu\n";
        let findings = scan_dockerfile("Dockerfile", content);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].tag, "latest");
    }

    #[test]
    fn detects_from_case_insensitive() {
        let content = "from nginx:stable\n";
        let findings = scan_dockerfile("Dockerfile", content);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].image, "nginx");
    }

    #[test]
    fn multi_stage_dockerfile() {
        let content = "FROM rust:1.75 AS builder\nRUN cargo build\nFROM debian:bookworm-slim\n";
        let findings = scan_dockerfile("Dockerfile", content);
        assert_eq!(findings.len(), 2);
    }

    #[test]
    fn compose_detects_unpinned() {
        let content = "services:\n  db:\n    image: postgres:16\n";
        let findings = scan_compose_file("docker-compose.yml", content);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].image, "postgres");
        assert_eq!(findings[0].tag, "16");
    }

    #[test]
    fn compose_ignores_digest_pinned() {
        let content = "services:\n  db:\n    image: postgres:16@sha256:abc\n";
        let findings = scan_compose_file("docker-compose.yml", content);
        assert!(findings.is_empty());
    }

    #[test]
    fn compose_defaults_to_latest() {
        let content = "services:\n  web:\n    image: nginx\n";
        let findings = scan_compose_file("docker-compose.yml", content);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].tag, "latest");
    }
}
