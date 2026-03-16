# Documentation Style

Severity: **warning**. Violations of these rules produce `WARNING` comments but do not trigger `STATUS: FAILED`. Only flag clear, obvious violations – do not nitpick borderline cases.

## Tone and Style

### Language

- Write all documentation in English
- Use simple, clear language – avoid idioms, humor, and cultural references unless necessary
- Prioritize clarity over elegance
- Use short, direct sentences
- Use **American English** spelling consistently ("color", "authorize", "behavior")

### Voice and Tense

- Use **active voice**: "The API returns an error" instead of "An error is returned"
- Use **present tense**: describe the system's current state, not what it "will" or "should" do

### Precision and Brevity

- Include only what the reader needs to complete a task or understand a concept
- Be specific: "The process runs every 10 minutes" instead of "The process runs regularly"
- Avoid filler phrases like "It should be noted that…" or "Basically…"

### Consistency and Neutrality

- Use consistent terminology across all documents – if a term exists in the product, use it exactly
- Maintain a neutral, professional tone
- Avoid personal pronouns except in clear instructions ("You can run…", "We deploy…") – keep pronouns gender-neutral when needed
- Use full words instead of abbreviations unless the abbreviation is widely recognized – spell out abbreviations on first use

## Structure and Format

### General Layout

- Use [GitHub Flavored Markdown (GFM)](https://github.github.com/gfm/) for all internal and repository documentation
- Start each document with a one-line summary of its contents (e.g. *"This document describes the deployment and configuration of the user service."*)
- Use ATX-style headings (`#`, `##`, `###`) to structure topics logically
- Keep paragraphs short – 3 to 5 sentences each
- Use bulleted lists for unordered information and numbered lists for sequential steps
- Avoid nesting lists more than one level deep
- Include a table of contents for documents with more than 3 headings
