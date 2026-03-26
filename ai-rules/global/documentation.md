---
description: The 5-level documentation framework governing all project documentation.
globs: "**/*.dart, **/*.md"
---

# 5-Level Documentation Framework

All documentation MUST be in **English**. Be **concise and precise** — explain the "why", skip the obvious "what". No AI-generated filler, no restating what the code already says. Documentation must be updated when code changes (enforced via PR checklist).

---

## Level 1 — Project Level

Top-level documents that every contributor reads first.

| Document | Purpose |
|----------|---------|
| `README.md` | Project overview, setup instructions, quick start |
| `CONTRIBUTING.md` | Contribution workflow, PR process, code review expectations |
| `CHANGELOG.md` | Notable changes per release (Keep a Changelog format) |
| `docs/README.md` | Index of project documentation |
| `docs/adopting.md` | How to adopt standards in a consumer repo (this project) |

---

## Level 2 — Architecture & Decisions

Structural documentation explaining the system design and the reasoning behind key decisions.

### Architecture Docs (`docs/architecture/`)

High-level and module-specific architecture documents. Each explains the design, data flow, and key constraints of a system area.

### ADRs (`docs/adr/`)

Architecture Decision Records capture the "why" behind significant technical choices. Use **MADR format**:

```markdown
# ADR-NNN: [Title]

## Status
[Proposed | Accepted | Deprecated | Superseded by ADR-NNN]

## Context
[2-4 sentences: what problem existed, what forces were at play]

## Decision
[2-4 sentences: what we decided, active voice]

## Consequences
- (+) [positive outcomes]
- (-) [trade-offs]
```

**When to create an ADR:**
- New architectural pattern or framework adoption
- Significant structural change (feature splits, module reorganization)
- Cross-cutting concern decisions (error handling strategy, state management approach)

---

## Level 3 — Module/Feature Level

Every feature (`lib/features/<name>/`) and every core module (`lib/core/<name>/`) MUST have a `README.md`.

### Mandatory README Template

```markdown
# [Module Name]

[One sentence: what this module does.]

## Responsibilities
- [Bullet points]

## Structure
[Directory tree]

## Dependencies
**Core:** ...
**Packages:** ...

## API
[Public widgets, controllers, providers with usage examples]

## Testing
[Test command + brief strategy note]
```

**Rules:**
- Keep it under 150 lines — link to detailed docs instead of inlining everything
- Update the README when public API changes
- The "Structure" section uses a directory tree, not prose

---

## Level 4 — Code Level

### Doc Comments (`///`)

Required for **all** public API elements. Focus on intent, contracts, and non-obvious behavior.

| Element | Requirement | Example |
|---------|-------------|---------|
| **Class** | Purpose, key responsibilities | `/// Manages user authentication via OIDC.` |
| **Method** | What it does, parameters, return value, side effects | `/// Returns [LoginResult] — never throws.` |
| **Provider** | What state it exposes, dependencies | `/// Provides the current user's profile, refreshed on login.` |
| **Enum** | Purpose of the enum + each value | `/// The phase of timeline scroll behavior.` |
| **Model/Entity fields** | Every field must have a `///` comment | `/// The user's display name, or null if not set.` |
| **Extension** | What it extends and why | `/// Adds download helpers to [Client].` |

**Models and entities are NOT exempt.** Every field on a domain model, state class, or result type must be documented:

```dart
/// The result of a successful login.
final class LoginSuccess extends LoginResult {
  /// The Matrix user ID returned by the server.
  final String userId;

  /// The access token for subsequent API calls.
  final String accessToken;

  const LoginSuccess({required this.userId, required this.accessToken});
}
```

### Inline Comments (`//`)

Only for non-obvious logic. Explain **"why"**, not "what":

```dart
// Delay needed because Matrix server needs time to propagate the event
await Future.delayed(const Duration(milliseconds: 100));
```

### Forbidden Patterns

| Pattern | Reason |
|---------|--------|
| Commented-out code | Use version control |
| `// TODO:` without issue reference | Untrackable — use `// TODO(#123): ...` |
| `// CRITICAL:`, `// IMPORTANT:`, `// NOTE:` | Noise — if it's critical, the code should reflect it |
| Migration history in comments | Belongs in git, not in code |
| Restating the obvious | `/// Returns the name.` on `String get name` adds nothing |

---

## Level 5 — Test Documentation

### Test Utility Docs

`test/utils/README.md` documents the test infrastructure: mock factories, builders, helpers, and how to use them.

### Test Group Documentation

Every test file should have descriptive `group()` and `test()` names that read as specifications:

```dart
group('LoginController', () {
  group('submit', () {
    test('sets loading state while awaiting result', () { ... });
    test('returns success when credentials are valid', () { ... });
    test('returns failure with network error on timeout', () { ... });
  });
});
```

### Testing Strategy

`docs/testing_strategy.md` covers:
- Test pyramid (unit > widget > integration)
- Mocking approach
- Coverage goals
- Test naming conventions
- Integration test setup

---

## Enforcement

- **PR checklist** includes: `Documentation updated (README, doc comments, ADR if architectural change)`
- **Code review** should flag missing `///` on public API
- When modifying a module's public API, its README must be updated in the same PR
