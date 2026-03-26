//! Anthropic Claude API client for AI code reviews.

use serde::{Deserialize, Serialize};
use snafu::ResultExt;

use crate::error::{self, Result};

const CLAUDE_API_URL: &str = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL: &str = "claude-sonnet-4-20250514";
const MAX_TOKENS: u32 = 4096;

/// Result of an AI code review including findings and token usage.
#[derive(Debug)]
pub struct ReviewResult {
    /// Number of ERROR-level findings.
    pub errors: usize,
    /// Number of WARNING-level findings.
    pub warnings: usize,
    /// Brief overall assessment from the AI.
    pub summary: String,
    /// Inline review comments to post on the PR.
    pub comments: Vec<ReviewComment>,
    /// Claude model ID used for the review.
    pub model: String,
    /// Total tokens consumed (input + output).
    pub tokens_used: usize,
}

/// A single inline review comment on a specific file and line.
#[derive(Debug, Serialize)]
pub struct ReviewComment {
    /// File path relative to the repo root.
    pub path: String,
    /// Line number in the file.
    pub line: u32,
    /// `ERROR` or `WARNING`.
    pub severity: String,
    /// Human-readable description of the issue.
    pub message: String,
}

#[derive(Serialize)]
struct ClaudeRequest {
    model: String,
    max_tokens: u32,
    system: String,
    messages: Vec<ClaudeMessage>,
}

#[derive(Serialize)]
struct ClaudeMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct ClaudeResponse {
    content: Vec<ClaudeContent>,
    model: String,
    usage: ClaudeUsage,
}

#[derive(Deserialize)]
struct ClaudeContent {
    text: Option<String>,
}

#[derive(Deserialize)]
struct ClaudeUsage {
    input_tokens: usize,
    output_tokens: usize,
}

#[tracing::instrument(skip_all, name = "claude::review_diff")]
pub async fn review_diff(
    http_client: &reqwest::Client,
    api_key: &str,
    rules: &str,
    diff: &str,
) -> Result<ReviewResult> {
    const MAX_DIFF_BYTES: usize = 100_000;
    let truncated_diff = if diff.len() > MAX_DIFF_BYTES {
        &diff[..diff.floor_char_boundary(MAX_DIFF_BYTES)]
    } else {
        diff
    };

    let system_prompt = format!(
        r#"You are an engineering standards reviewer. Review the following PR diff against the provided rules.

RULES:
{rules}

OUTPUT FORMAT:
Respond with valid JSON only, no markdown fences. Use this schema:
{{
  "summary": "Brief overall assessment",
  "findings": [
    {{
      "path": "file/path.rs",
      "line": 42,
      "severity": "ERROR" or "WARNING",
      "message": "Description of the issue"
    }}
  ]
}}

GUIDELINES:
- Only report findings that violate the provided rules.
- Use ERROR for definite violations. Use WARNING for style suggestions.
- Be specific: reference the rule being violated.
- If the diff is clean, return an empty findings array.
- Do not invent findings. If unsure, skip it."#
    );

    let request = ClaudeRequest {
        model: DEFAULT_MODEL.into(),
        max_tokens: MAX_TOKENS,
        system: system_prompt,
        messages: vec![ClaudeMessage {
            role: "user".into(),
            content: format!("Review this PR diff:\n\n```diff\n{truncated_diff}\n```"),
        }],
    };

    let response = http_client
        .post(CLAUDE_API_URL)
        .header("x-api-key", api_key)
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&request)
        .send()
        .await
        .context(error::HttpClient)?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        tracing::error!(
            status = %status,
            response_body = %body,
            "Claude API request failed",
        );
        snafu::whatever!("Claude API returned {status}");
    }

    let claude_response: ClaudeResponse = response.json().await.context(error::HttpClient)?;

    let text = claude_response
        .content
        .first()
        .and_then(|c| c.text.as_deref())
        .unwrap_or("{}");

    let parsed = parse_review_response(text);

    Ok(ReviewResult {
        errors: parsed.errors,
        warnings: parsed.warnings,
        summary: parsed.summary,
        comments: parsed.comments,
        model: claude_response.model,
        tokens_used: claude_response.usage.input_tokens + claude_response.usage.output_tokens,
    })
}

#[derive(Deserialize, Default)]
struct ParsedReview {
    summary: Option<String>,
    findings: Option<Vec<ParsedFinding>>,
}

#[derive(Deserialize)]
struct ParsedFinding {
    path: String,
    line: u32,
    severity: String,
    message: String,
}

struct ParsedResult {
    errors: usize,
    warnings: usize,
    summary: String,
    comments: Vec<ReviewComment>,
}

fn parse_review_response(text: &str) -> ParsedResult {
    let mut cleaned = text.trim();
    if let Some(stripped) = cleaned.strip_prefix("```json") {
        cleaned = stripped.trim();
    } else if let Some(stripped) = cleaned.strip_prefix("```") {
        cleaned = stripped.trim();
    }
    if let Some(stripped) = cleaned.strip_suffix("```") {
        cleaned = stripped.trim();
    }

    let parsed: ParsedReview = match serde_json::from_str(cleaned) {
        Ok(p) => p,
        Err(e) => {
            tracing::warn!(
                error = %e,
                response_preview = &cleaned[..cleaned.len().min(200)],
                "failed to parse Claude review response — reporting as inconclusive",
            );
            return ParsedResult {
                errors: 0,
                warnings: 1,
                summary: "Review inconclusive: AI response could not be parsed.".into(),
                comments: vec![],
            };
        }
    };

    let findings = parsed.findings.unwrap_or_default();
    let errors = findings.iter().filter(|f| f.severity == "ERROR").count();
    let warnings = findings.iter().filter(|f| f.severity == "WARNING").count();

    let comments = findings
        .into_iter()
        .map(|f| ReviewComment {
            path: f.path,
            line: f.line,
            severity: f.severity,
            message: f.message,
        })
        .collect();

    ParsedResult {
        errors,
        warnings,
        summary: parsed.summary.unwrap_or_else(|| "No issues found.".into()),
        comments,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_valid_json() {
        let input = r#"{"summary": "Looks good", "findings": [{"path": "src/main.rs", "line": 10, "severity": "ERROR", "message": "unused import"}]}"#;
        let result = parse_review_response(input);
        assert_eq!(result.errors, 1);
        assert_eq!(result.warnings, 0);
        assert_eq!(result.summary, "Looks good");
        assert_eq!(result.comments.len(), 1);
        assert_eq!(result.comments[0].path, "src/main.rs");
    }

    #[test]
    fn strips_markdown_fences() {
        let input = "```json\n{\"summary\": \"OK\", \"findings\": []}\n```";
        let result = parse_review_response(input);
        assert_eq!(result.summary, "OK");
        assert_eq!(result.errors, 0);
    }

    #[test]
    fn empty_findings_reports_no_issues() {
        let input = r#"{"summary": "Clean", "findings": []}"#;
        let result = parse_review_response(input);
        assert_eq!(result.errors, 0);
        assert_eq!(result.warnings, 0);
        assert_eq!(result.summary, "Clean");
    }

    #[test]
    fn invalid_json_returns_inconclusive() {
        let result = parse_review_response("this is not json at all");
        assert_eq!(result.warnings, 1);
        assert!(result.summary.contains("inconclusive"));
        assert!(result.comments.is_empty());
    }

    #[test]
    fn counts_errors_and_warnings_separately() {
        let input = r#"{"findings": [
            {"path": "a.rs", "line": 1, "severity": "ERROR", "message": "bad"},
            {"path": "b.rs", "line": 2, "severity": "WARNING", "message": "meh"},
            {"path": "c.rs", "line": 3, "severity": "ERROR", "message": "worse"}
        ]}"#;
        let result = parse_review_response(input);
        assert_eq!(result.errors, 2);
        assert_eq!(result.warnings, 1);
    }

    #[test]
    fn missing_summary_defaults() {
        let input = r#"{"findings": []}"#;
        let result = parse_review_response(input);
        assert_eq!(result.summary, "No issues found.");
    }
}
