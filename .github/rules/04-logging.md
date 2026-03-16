# Logging Policy

## Log Levels

Log levels MUST be used according to the following definitions:

| Level | Definition | Production usage |
|-------|-----------|-----------------|
| **ERROR** | The operation failed or a feature is broken. Something has unambiguously gone wrong. | Use sparingly. Every logged ERROR should be infrequent enough to enable automated alerting without causing overwhelm. |
| **WARN** | A potential issue that is not immediately critical but could cause problems in the future. | Acceptable in production. Useful for identifying patterns that lead to future errors. |
| **INFO** | Normal operational events and audit-relevant actions. | Default production level. Report routine system events without overwhelming the logs. |
| **DEBUG** | Detailed diagnostic information for troubleshooting. | Enable temporarily in production when investigating specific issues. Disable immediately after. |
| **TRACE** | Very detailed, low-level execution flow information. | MUST NOT be used in production. Strictly reserved for local development and staging environments. |

## Structured Logging

- Use structured logging (key-value pairs), not string concatenation
- Log messages MAY include a `category` field for filtering and querying
- Category values MUST be in `SCREAMING_SNAKE_CASE` (e.g. `AUDIT`, `GENERAL`)

## Privacy and Secrets

- **PII masking**: personally identifiable information (email addresses, display names, phone numbers) MUST be pseudonymized in ERROR, WARN, INFO, and DEBUG logs. Opaque identifiers (UUIDs, internal user IDs) are acceptable.
- **Secrets redaction**: logs MUST NOT contain passwords, API keys, tokens, or sensitive API headers. Secrets MUST be redacted in the component before log ingestion.

## Audit Logging

INFO level logs MUST include significant audit-relevant events:
- Administrative actions (user account changes, role assignments)
- User privilege changes
- Key configuration changes

Audit logs MUST adhere to the same PII masking rules.

## Error Messages

Error messages shown to end users are separate from logs and MUST follow different rules:

- Target end users, not developers
- NEVER expose stack traces, internal error details, or system paths
- Follow [Google's error message guidelines](https://developers.google.com/tech-writing/error-messages)
