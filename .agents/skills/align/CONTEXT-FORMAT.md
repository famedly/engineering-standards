# CONTEXT.md format

A `CONTEXT.md` is a glossary for one domain — nothing else. It fixes the words the team uses so code, docs, and conversation stay aligned.

## Shape

```md
# {Context name}

{One or two sentences: what this context covers and why it exists.}

## Language

**Room**:
A Matrix room: a set of members sharing one event timeline.
_Avoid_: channel, chat, group

**Practitioner**:
A healthcare professional who acts in the system on behalf of an organization.
_Avoid_: doctor, user, staff

**Patient**:
The natural person a health record belongs to, distinct from the user operating the system.
_Avoid_: user, account, client
```

## Rules

- **Pick one word per concept.** List the rejected synonyms under `_Avoid_`.
- **One or two sentences.** Say what the term _is_, not what it does.
- **Context-specific only.** Skip general engineering terms (timeouts, error enums, `famedly-rust-utils` helpers). Ask: is this concept unique to this domain? If not, leave it out.
- **Cluster under subheadings** when groups emerge; a flat list is fine for one tight area.

## Where it lives

One `CONTEXT.md` at the repo root, created the first time a term is pinned down. If a repo ever grows several distinct domains, drop a `CONTEXT.md` into each subtree and use the one nearest the code in play — no central index needed for now.
