//! Language and ecosystem scope detection from repository file trees.

use crate::error::Result;

/// Known language/ecosystem scopes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Scope {
    /// Dart / Flutter projects (detected via `pubspec.yaml`).
    Dart,
    /// Rust projects (detected via `Cargo.toml`).
    Rust,
    /// TypeScript / JavaScript projects (detected via `tsconfig.json` or `package.json`).
    TypeScript,
    /// Python projects (detected via `pyproject.toml`, `requirements.txt`, etc.).
    Python,
    /// Docker-based projects (detected via `Dockerfile` or `docker-compose.*`).
    Docker,
    /// Terraform infrastructure (detected via `*.tf` files).
    Terraform,
    /// Helm charts (detected via `Chart.yaml`).
    Helm,
}

impl Scope {
    /// Returns the lowercase string representation used in config and DB.
    #[must_use]
    pub fn as_str(&self) -> &'static str {
        match self {
            Scope::Dart => "dart",
            Scope::Rust => "rust",
            Scope::TypeScript => "typescript",
            Scope::Python => "python",
            Scope::Docker => "docker",
            Scope::Terraform => "terraform",
            Scope::Helm => "helm",
        }
    }
}

impl std::fmt::Display for Scope {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Marker files: presence of ANY of these in the tree identifies the scope.
const SCOPE_MARKERS: &[(Scope, &[&str])] = &[
    (Scope::Dart, &["pubspec.yaml"]),
    (Scope::Rust, &["Cargo.toml"]),
    (
        Scope::TypeScript,
        &["tsconfig.json", "package.json"],
    ),
    (
        Scope::Python,
        &["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"],
    ),
    (
        Scope::Docker,
        &["Dockerfile", "docker-compose.yml", "docker-compose.yaml"],
    ),
];

/// Glob-style suffix matches (filename ends with pattern suffix).
const SCOPE_GLOBS: &[(Scope, &str)] = &[
    (Scope::Terraform, "*.tf"),
    (Scope::Helm, "Chart.yaml"),
];

/// Detects language scopes from a list of file paths in the repository.
#[must_use]
pub fn detect_scopes(file_paths: &[String]) -> Vec<Scope> {
    let mut scopes = Vec::new();

    for &(scope, markers) in SCOPE_MARKERS {
        if markers.iter().any(|m| {
            file_paths
                .iter()
                .any(|p| p == m || p.ends_with(&format!("/{m}")))
        }) {
            scopes.push(scope);
        }
    }

    for &(scope, pattern) in SCOPE_GLOBS {
        if scopes.contains(&scope) {
            continue;
        }
        let matched = file_paths.iter().any(|p| {
            let filename = p.rsplit('/').next().unwrap_or(p);
            filename == pattern || (pattern.starts_with('*') && filename.ends_with(&pattern[1..]))
        });
        if matched {
            scopes.push(scope);
        }
    }

    scopes
}

/// Fetches the full recursive file tree via the Git Trees API and detects scopes.
///
/// Uses the Git Trees API (`/git/trees/{sha}?recursive=1`) instead of the
/// Content API so that files in subdirectories are found reliably.
#[tracing::instrument(skip_all, fields(%owner, %repo))]
pub async fn detect_scopes_for_repo(
    github: &octocrab::Octocrab,
    owner: &str,
    repo: &str,
) -> Result<Vec<Scope>> {
    let repo_info = match github.repos(owner, repo).get().await {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!(%owner, %repo, error = %e, "could not fetch repo info for scope detection");
            return Ok(vec![]);
        }
    };
    let default_branch = repo_info
        .default_branch
        .unwrap_or_else(|| "main".into());

    let head_ref = match github
        .repos(owner, repo)
        .get_ref(&octocrab::params::repos::Reference::Branch(
            default_branch.clone(),
        ))
        .await
    {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!(%owner, %repo, error = %e, "could not resolve HEAD ref for scope detection");
            return Ok(vec![]);
        }
    };

    let head_sha = match &head_ref.object {
        octocrab::models::repos::Object::Commit { sha, .. } => sha.clone(),
        _ => {
            tracing::warn!(%owner, %repo, "unexpected ref object type");
            return Ok(vec![]);
        }
    };

    let tree_url = format!("/repos/{owner}/{repo}/git/trees/{head_sha}?recursive=1");
    let tree: serde_json::Value = match github.get(tree_url, None::<&()>).await {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(%owner, %repo, error = %e, "could not fetch git tree for scope detection");
            return Ok(vec![]);
        }
    };

    let file_paths: Vec<String> = tree
        .get("tree")
        .and_then(|t| t.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|entry| entry.get("path")?.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();

    tracing::debug!(%owner, %repo, count = file_paths.len(), "fetched git tree for scope detection");
    Ok(detect_scopes(&file_paths))
}

/// Converts scopes to string list for database storage.
#[must_use]
pub fn scopes_to_strings(scopes: &[Scope]) -> Vec<String> {
    scopes.iter().map(|s| s.as_str().to_owned()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_dart_from_pubspec() {
        let files = vec!["pubspec.yaml".into(), "lib/main.dart".into()];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::Dart));
    }

    #[test]
    fn detects_multiple_scopes() {
        let files = vec![
            "Cargo.toml".into(),
            "Dockerfile".into(),
            "infra/main.tf".into(),
        ];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::Rust));
        assert!(scopes.contains(&Scope::Docker));
        assert!(scopes.contains(&Scope::Terraform));
    }

    #[test]
    fn empty_files_returns_no_scopes() {
        assert!(detect_scopes(&[]).is_empty());
    }

    #[test]
    fn detects_marker_in_subdirectory() {
        let files = vec!["packages/api/Cargo.toml".into()];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::Rust));
    }

    #[test]
    fn does_not_detect_partial_filename_match() {
        let files = vec!["not-a-Cargo.toml.bak".into()];
        let scopes = detect_scopes(&files);
        assert!(!scopes.contains(&Scope::Rust));
    }

    #[test]
    fn detects_python_from_pyproject() {
        let files = vec!["pyproject.toml".into()];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::Python));
    }

    #[test]
    fn detects_python_from_requirements_txt() {
        let files = vec!["requirements.txt".into()];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::Python));
    }

    #[test]
    fn detects_helm_from_chart_yaml() {
        let files = vec!["charts/myapp/Chart.yaml".into()];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::Helm));
    }

    #[test]
    fn detects_typescript_from_tsconfig() {
        let files = vec!["tsconfig.json".into(), "src/index.ts".into()];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::TypeScript));
    }

    #[test]
    fn detects_docker_compose_yaml() {
        let files = vec!["docker-compose.yaml".into()];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::Docker));
    }

    #[test]
    fn terraform_glob_in_subdirectory() {
        let files = vec!["infra/prod/vpc.tf".into()];
        let scopes = detect_scopes(&files);
        assert!(scopes.contains(&Scope::Terraform));
    }

    #[test]
    fn no_duplicate_scopes() {
        let files = vec![
            "Cargo.toml".into(),
            "crates/lib/Cargo.toml".into(),
        ];
        let scopes = detect_scopes(&files);
        assert_eq!(scopes.iter().filter(|s| **s == Scope::Rust).count(), 1);
    }

    #[test]
    fn scope_display_roundtrip() {
        for scope in [
            Scope::Dart, Scope::Rust, Scope::TypeScript,
            Scope::Python, Scope::Docker, Scope::Terraform, Scope::Helm,
        ] {
            assert!(!scope.as_str().is_empty());
            assert_eq!(scope.to_string(), scope.as_str());
        }
    }

    #[test]
    fn scopes_to_strings_preserves_order() {
        let scopes = vec![Scope::Rust, Scope::Docker];
        let strings = scopes_to_strings(&scopes);
        assert_eq!(strings, vec!["rust", "docker"]);
    }
}
