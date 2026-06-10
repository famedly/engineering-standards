---
name: align
description: Pressure-test a plan or design with the engineer until it is fully aligned, walking every branch of the decision tree and checking it against Famedly's documented language (CONTEXT.md) and decisions (ADRs), updating those docs as agreement lands. Decisions are raised as multiple-choice prompts through the agent's question tool; when aligned, optionally captures the result as a PRD (Notion, Jira, or repo). Use when the user wants to create a plan, yet also invoke this skill proactively before starting any non-trivial change: one carrying genuine design choices or ambiguity, or spanning multiple files, unfamiliar code, or real research. Skip trivial, well-specified edits (a rename, a one-liner, a typo).
---

<job>

Drive the plan to alignment. Take the decision tree branch by branch, settle dependencies before the choices that rest on them, and put a recommended answer on every decision.

Answer your own questions from the code first — search the repo, read the relevant crate/module — and only bring me what truly needs my intent or domain knowledge.

</job>

<when-to-engage>

Engage proactively, before starting the work — not only on an explicit "align" invocation. A change is worth aligning on when it carries genuine design choices or ambiguity, or when it spans multiple files, unfamiliar code, or real research. A trivial, well-specified edit — a rename, a one-liner, a typo fix — needs none of this; just do it.

Right-size the effort to the task. Scale the number of rounds and the depth of grilling to the ambiguity and blast radius: a medium, mostly-clear change may need a single round on the one real decision, while a large or open-ended one earns the full tree. If exploring the code shows the task is actually trivial or already unambiguous, say so and drop straight into the work rather than manufacturing questions.

</when-to-engage>

<how-to-ask>

Raise decisions through whatever structured question tool the agent runtime exposes:

- **Cursor** → `AskQuestion` or similar,
- **Claude Code / Claude CLI** → `AskUserQuestion` or similar,
- **none tool available** → ask questions in chat one by one.

For each question:

1. Group related but independent decisions together (1–5 per round). Resolve upstream choices first; only ask dependent follow-ups once their parent is settled.
2. Lead with your recommended option, tag it `Recommended:`, and justify it in one line.
3. Give at least two real options plus a way for user to specify their own answer. Allow multi-select when several answers can hold at once.
4. Keep rounds going until the tree is exhausted, then restate the settled decisions back to me.

</how-to-ask>

<capture-the-outcome>

Once the tree is settled, summarize the agreed decisions. Then ask me — via the same question tool — how to capture them:

- **Keep in chat only** — the alignment lives in this conversation; write nothing.
- **Write a PRD** — produce the structured doc below. Then ask _where_: a Notion page, a Jira ticket, or a markdown file in the repo. Default to whatever I've used for this work already.

Synthesize the PRD from what we settled — do not re-interview me. Use `CONTEXT.md` vocabulary throughout; keep file paths and code snippets out (they rot), except a short snippet that pins a precise decision (a type, schema, or state machine).

```md
# {Title}

## Problem

{The problem, from the user's view.}

## Solution

{The chosen approach, from the user's view.}

## User stories

1. As a {actor}, I want {capability}, so that {benefit}.
   {Cover every facet we aligned on.}

## Decisions

{Modules touched, interfaces, schema/API contracts, trade-offs settled, the test seams (prefer existing, highest possible).}

## Out of scope

{What we deliberately excluded.}
```

</capture-the-outcome>

<check-against-the-docs>

While exploring, pull in the project's domain docs and verify the plan against them.

**Locate them:** expect a `CONTEXT.md` plus `docs/adr/` at the repo root (or the nearest one to the code in play). Write these files only once you have something concrete to record and I've confirmed docs should be created.

During the alignment:

- **Term clashes** — when I use a word against its `CONTEXT.md` meaning, stop me: "Glossary says 'room' is X; you mean Y — which holds?"
- **Vague words** — offer a precise canonical term ("'user' — the account, the Matrix user, or the patient?").
- **Edge scenarios** — invent concrete cases (federation, multi-tenant, gematik/ePA flows, GDPR deletion) to force sharp boundaries.
- **Code reality** — when a claim conflicts with the code, name the contradiction.
- **Record terms live** in `CONTEXT.md` as they settle — never batch. It stays a pure glossary: no implementation, specs, or notes. See [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).
- **Suggest an ADR only** when the call is costly to undo, non-obvious to a later reader, and a genuine trade-off. Otherwise skip. See [ADR-FORMAT.md](./ADR-FORMAT.md).

</check-against-the-docs>
