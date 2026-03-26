---
description: Behavior rules for AI agents — prevents over-engineering, scope creep, and vibe coding.
alwaysApply: true
---

# Agent Behavior Rules

## The Prime Directive: Do Exactly What Was Asked

Change only what was explicitly requested. Do NOT:
- Refactor code that was not mentioned
- Add features that were not requested
- "Improve" adjacent code while fixing something else
- Introduce new patterns because they seem better or cleaner

If you notice something worth improving that was NOT asked about, mention it in text — do not implement it.

---

## Scope

- **Edit existing files.** Creating a new file requires explicit justification.
- Touch the **minimum number of files** necessary to complete the task.
- If the fix is in one function, do not rewrite the class.
- If the task is a rename, do only the rename — nothing else.
- If one line needs to change, change one line.

---

## Simplicity

- The simplest solution that satisfies the requirement is the correct solution.
- Do not add abstraction layers for hypothetical future use cases ("we might need this later").
- Do not extract a helper function unless it is called 2+ times or genuinely reduces complexity.
- Do not introduce an interface or abstract class unless multiple implementations exist or are explicitly planned.
- Do not split a file into multiple files unless the task requires it.

---

## Comments

- Do not add comments that restate what the code does (`// Increment the counter` above `counter++`).
- Do not add section dividers like `// --- Setup ---` or `// Handle error`.
- Only add a comment when the **why** behind the code is genuinely non-obvious and not captured by naming.
- Do not add doc comments (`///`) to code that was not touched by the task.

---

## Do Not Add Unrequested

Unless explicitly asked, do NOT add:
- Loading states, error states, or retry logic
- Logging or analytics calls
- Tests or test helpers
- TODOs or FIXMEs
- Documentation or README updates for unchanged code
- `const`, `final`, or `Semantics` fixes on lines not related to the task
- `RepaintBoundary`, `.select()`, or other performance optimizations
- Input validation beyond what the task describes

---

## Follow Existing Patterns

- Match the style and patterns of the surrounding code, even if you personally prefer a different approach.
- Do not switch between `switch` and `if/else` unless that is the task.
- Do not convert a `StatelessWidget` to a `ConsumerWidget` unless Riverpod access is required by the task.
- Do not reorganize imports unless import cleanup is the task.
- Do not reformat code blocks that are not being changed.
- If the existing code uses a pattern that differs from the rules in `architecture.mdc`, note the deviation but do not fix it unless the task is explicitly a refactoring task.

---

## When Uncertain

- **Ask before implementing** something that is ambiguous or has multiple valid approaches.
- Prefer a smaller, correct change over a larger, uncertain one.
- If multiple implementation options exist, describe the trade-offs in 2-3 sentences and ask which direction to take.
- Never guess at intent — a wrong large change is worse than a clarifying question.
