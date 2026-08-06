## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (config.famedly.standards.ci) steps;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }: {
      options.famedly.standards.release = {
        enable = lib.mkEnableOption ''
          publishing a GitHub release for every version tag

          A tag says a version exists; the release says what changed in it
        '';

        changelog = lib.mkOption {
          description = ''
            File the release notes are taken from.

            The section whose heading names the version is used, whichever
            heading level it is written at. A file that is missing or says
            nothing about this version falls back to GitHub's summary of the
            commits, since by then the tag is already pushed.
          '';

          type = lib.types.str;
          default = "CHANGELOG.md";
        };
      };
    }
  );

  config.perSystem =
    { config, ... }:
    let
      cfg = config.famedly.standards.release;
    in
    lib.mkIf cfg.enable {
      githubActions.workflows.release = {
        name = "Publish a release for the tag";

        on.push.tags = [ "v*" ];

        jobs.release = {
          runsOn = "ubuntu-latest";

          timeoutMinutes = 10;

          # The only write this workflow makes.
          permissions.contents = "write";

          steps = steps.checkout ++ [
            {
              name = "Publish the release";

              env = {
                GH_TOKEN = "\${{ github.token }}";
                CHANGELOG = cfg.changelog;
                TAG = "\${{ github.ref_name }}";
              };

              run = ''
                version="''${TAG#v}"

                # awk exits non-zero on a file that is not there, which would
                # fail the run rather than fall back below.
                input="$CHANGELOG"
                test -f "$input" || input=/dev/null

                awk -v version="$version" '
                	BEGIN {
                		pattern = version
                		gsub(/\./, "\\.", pattern)

                		# Bounded on both sides, so that 1.2.3 answers neither for
                		# 1.2.30 nor for 1.2.3-rc.1.
                		pattern = "(^|[^0-9.])" pattern "([^0-9.-]|$)"
                	}

                	/^#+[[:space:]]/ {
                		match($0, /^#+/)
                		level = RLENGTH

                		# `### Fixed` under `## 1.2.3` belongs to the section, so
                		# only a heading at the same level or above ends it.
                		if (found) {
                			if (level <= depth) exit
                		} else {
                			heading = $0
                			sub(/^#+[[:space:]]*/, "", heading)

                			if (heading ~ pattern) {
                				found = 1
                				depth = level
                				next
                			}
                		}
                	}

                	found { print }
                ' "$input" >notes.md

                flags=(--title "$version")
                created=()

                # Everything semver spells with a hyphen is a prerelease.
                case "$TAG" in
                	*-*) flags+=(--prerelease) ;;
                esac

                if test -s notes.md; then
                	flags+=(--notes-file notes.md)
                else
                	echo "::warning::$CHANGELOG says nothing about $version, falling back to the commit summary"

                	# Only generated on creation, so a rerun leaves the notes
                	# already there.
                	created+=(--generate-notes)
                fi

                # Created or edited, so that a rerun finishes the job instead
                # of failing on what the first attempt managed.
                if gh release view "$TAG" >/dev/null 2>&1; then
                	gh release edit "$TAG" "''${flags[@]}"
                else
                	gh release create "$TAG" --verify-tag "''${flags[@]}" "''${created[@]}"
                fi
              '';
            }
          ];
        };
      };
    };
}
