# Code Quality Standards

## Core Principles

- **No code duplication** – abstract shared functionality into functions or classes
- **KISS** – follow the [Keep It Simple, Stupid](https://en.wikipedia.org/wiki/KISS_principle) principle
- Use descriptive names for variables, classes, and functions to minimize the need for comments
- Every new feature MUST include tests. PRs without tests for new functionality MUST NOT be merged.

## Workarounds and Non-Obvious Implementations

All workarounds and non-obvious implementations MUST be documented:

1. Include links to relevant issues, PRs, documentation, Stack Overflow, or other sources
2. Add `HOURS WASTED: X` to workarounds that took significant debugging effort
3. For technical debt, create an issue with the label `tech debt` for future resolution

