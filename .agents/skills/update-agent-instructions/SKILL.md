---
name: update-agent-instructions
description: Updates Famedly engineering-standards agent-facing instructions (`AGENTS.md`, `CLAUDE.md`, `.agents/skills/*/SKILL.md`) to match the current repo state. Use when adding, removing or renaming a skill, when the AGENTS.md layout map / golden rules / foot-guns drift from reality, when CLAUDE.md needs adjusting, or when the user asks to update agent instructions.
---

# Update agent-facing instructions

The agent-instruction surface is small and layered: [`AGENTS.md`](../../../AGENTS.md) is the canonical document, [`CLAUDE.md`](../../../CLAUDE.md) is a vendor-specific stub that imports it, and each [`.agents/skills/<name>/SKILL.md`](../../../.agents/skills) is an operational recipe for one recurring task.

## Surface owned by this skill

| File | Purpose |
|------|---------|
| [`AGENTS.md`](../../../AGENTS.md) | Canonical, vendor-neutral. Sections: 1 purpose, 2 layout map, 3 golden rules, 4 change-recipe skill index, 5 verification, 6 dev shell tools, 7 commit hygiene, 8 foot-guns. |
| [`CLAUDE.md`](../../../CLAUDE.md) | Stub only. Must remain exactly `@AGENTS.md` (the Claude Code import directive). Do not expand it. |
| [`.agents/skills/<name>/SKILL.md`](../../../.agents/skills) | Project skills. One directory per skill. |

## Format rules for skills

- **Layout**: `.agents/skills/<kebab-name>/SKILL.md`. No supporting files unless genuinely required.
- **Frontmatter**: `name` (kebab-case, ≤64 chars, MUST match the directory name) and `description` (third person, includes WHAT and WHEN, includes trigger terms the user is likely to say).
- **Body**: well under 500 lines. Use markdown tables for enumerations. Reference reality with relative markdown links — from a skill at `.agents/skills/<x>/SKILL.md` the repo root is `../../../`.
- **Voice**: vendor-neutral. No Claude / Cursor / OpenAI branding inside the skill body. The skills serve every agent that respects the spec.

## Drift audit (sources of truth)

| AGENTS.md / CLAUDE.md location | Source of truth | Enumerate with |
|--------------------------------|-----------------|----------------|
| Section 4 skill-index table in `AGENTS.md` | Sub-directories of `.agents/skills/` | `ls -1 .agents/skills/` |
| Section 2 layout map in `AGENTS.md` | Top-level repo entries plus contents of `nix/modules/` | `ls -1` and `ls -1 nix/modules/` |
| Section 3 golden rules / Section 8 foot-guns | The actual checks in `flake.nix` and the conventions encoded in `nix/modules/` (e.g. `_internal.managedFiles`, action SHA pinning, `workflow_call` ban) | Code review — re-derive when modules change |
| `CLAUDE.md` | The Claude Code import-directive convention | `cat CLAUDE.md` MUST equal `@AGENTS.md\n` |
| Every relative link inside any changed `SKILL.md` | The actual file at the target path | Spot-check with `ls` or by clicking |

## Procedure

1. Identify which agent-instruction surface changed: `git diff --name-only $(git merge-base HEAD origin/main)..HEAD -- AGENTS.md CLAUDE.md '.agents/skills/**'`.
2. If a new skill was added or removed: update the section 4 table in [`AGENTS.md`](../../../AGENTS.md). Verify the new directory has `SKILL.md`, frontmatter `name` matches the directory, and `description` is third person with WHAT and WHEN.
3. If `nix/modules/` layout changed (file added, removed, or renamed): update the section 2 layout map in `AGENTS.md`.
4. If a new check was added in [`flake.nix`](../../../flake.nix), or a new convention was encoded in `nix/modules/`: re-evaluate sections 3 (golden rules) and 8 (foot-guns) and add or update bullets.
5. If user-facing docs were also affected, follow [`../update-user-docs/SKILL.md`](../update-user-docs/SKILL.md) in the same change.

## Conventions

- AGENTS.md is the only canonical instruction file. Do not duplicate its content into `CLAUDE.md` or per-skill bodies — link instead.
- Skills are operational (procedure + verification), not encyclopaedic. Push background into `AGENTS.md`; push user-facing reference into `docs/adopting.md`.
- Keep skill descriptions concise but trigger-rich: the description is what the agent loads at discovery time, the body is only loaded on invocation.

## Verification

- Run the audit commands above and confirm enumerations match the AGENTS.md tables.
- `cat CLAUDE.md` MUST output exactly `@AGENTS.md` (one line).
- Every relative link in a changed skill MUST resolve. Quick check: `rg -o '\]\(\.\.[^)]+\)' .agents/skills/<changed>/SKILL.md` then `ls` each target.
- No build is required for instruction-only changes.
