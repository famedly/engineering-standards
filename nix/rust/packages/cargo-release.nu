#!/usr/bin/env nu

## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0


# A release script for rust projects: bumps the version and updates the
# changelog.

def main [
	--major (-M)  # Treat as a major release
	--minor (-m)  # Treat as a minor release
	--force (-f)  # Ignore conflicting release type warnings
	--current-version (-V)  # Only print the package's current version
] {
	let version = (open Cargo.toml | get package.version)

	if $current_version {
		print $version
		return
	}

	let commits = (git log --oneline | lines)
	let breaking_changes = (
		$commits
		| take until {|l| $l =~ 'release!?:' }
		| where {|l| $l =~ '^[^:]+!: ' })
	let breaking_change = not ($breaking_changes | is-empty)

	def cmd [text: string] {
		print $"(ansi cyan)($text)(ansi reset)"
	}

	if $minor and $breaking_change {
		print "# Breaking changes detected:"
		print ($breaking_changes | str join (char newline))
		if not $force {
			exit 1
		}
		print "# Ignoring them"
	} else if $major and not $breaking_change {
		print "# No breaking changes detected"
		if not $force {
			exit 1
		}
	}

	let parts = ($version | split row '.' | into int)
	let new_version = if $major or ($breaking_change and not $minor) {
		$"($parts.0).($parts.1 + 1).0"
	} else {
		$"($parts.0).($parts.1).($parts.2 + 1)"
	}

	print $"# Bumping ($version) -> ($new_version)"

	# Replace the version inside the topmost manifest lines,
	# leaving the rest of the file alone.
	^sed -i $'1,10s/^version.*/version = "($new_version)"/' Cargo.toml

	# Update the crate's entries in the lockfile;
	# --workspace limits this to the workspace members' versions,
	# dependencies are not touched.
	^cargo update -q --workspace

	git-cliff -u -t $new_version -p CHANGELOG.md

	print '# Prepared the necessary changes,'
	print '# please review and adjust CHANGELOG.md, then run'
	cmd 'git commit -a -m "release: v$(cargo-release --current-version)"'
	print '# After merge to main:'
	cmd 'git tag -a -m "v$(cargo-release --current-version)" "v$(cargo-release --current-version)"'
	cmd 'git push --follow-tags'
}
