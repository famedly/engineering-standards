# Changelog

All notable changes to the engineering standards are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] – 2026-03-16

Initial release.

### Added

- General rules: documentation, code quality, documentation style, logging policy
- Language-specific rules: Dart/Flutter, Rust
- CI workflow (`claude-linter.yml`) – reusable workflow for PR code review via Claude
- Editor sync workflow (`sync-standards.yml`) – syncs rules to `.cursor/rules/` and `CLAUDE.md`
- Rollout script for distributing workflows to all org repos
