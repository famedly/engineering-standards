# ADR format

ADRs record _that_ a decision was made and _why_. They live in `docs/adr/`, numbered `0001-slug.md`, `0002-slug.md`, … Create the directory only when the first ADR is due.

## Template

```md
# {Decision in a short title}

{1–3 sentences: the situation, what we chose, and why.}
```

A single paragraph is enough. The worth is in the record, not in filling sections.

## Optional sections

Add only when they earn their place — most ADRs need none:

- **Status** (`proposed | accepted | deprecated | superseded by ADR-NNNN`) — when decisions get revisited.
- **Options considered** — when the rejected paths are worth remembering.
- **Consequences** — when downstream effects aren't obvious.

## Numbering

Take the highest number in `docs/adr/` and add one.

## When to write one

All three must hold:

1. **Costly to undo** — reversing later hurts.
2. **Non-obvious** — a future reader will ask "why this way?"
3. **A real trade-off** — there were live alternatives and you chose one deliberately.

Easy to reverse? Skip it. Obvious? Nobody will wonder. No alternative? Nothing to record.
