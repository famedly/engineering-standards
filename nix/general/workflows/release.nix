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
    { lib, ... }:
    {
      options.famedly.standards.release = {
        enable = lib.mkEnableOption ''
          publishing a GitHub release for every version tag

          A tag alone tells whoever is looking for a version that it exists and
          nothing else. The release carries what changed, and does so where
          people already look for it rather than in a file they have to find
        '';

        changelog = lib.mkOption {
          description = ''
            File the release notes are taken from.

            The section whose heading names the version is used, whichever
            heading level it is written at. When the file has nothing to say
            about this version, GitHub's own summary of the commits stands in:
            a release that says less is better than a tag that says nothing,
            and by the time the tag is pushed it is too late to fix the file.
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

          # Publishing a release is a write, and the only one this workflow
          # makes.
          permissions.contents = "write";

          steps = steps.checkout ++ [
            {
              name = "Publish the release";

              env = {
                GH_TOKEN = "\${{ github.token }}";
                CHANGELOG = cfg.changelog;
                TAG = "\${{ github.ref_name }}";
              };

              # A prerelease is one whose version carries a suffix — `v1.2.3-rc.1`
              # and everything else semver spells with a hyphen. Marking it keeps
              # it out of the place people read as "the current version".
              #
              # Created or edited, so that a rerun of a failed run finishes the
              # job instead of failing on what the first attempt managed.
              run = ''
                version="''${TAG#v}"

                awk -v version="$version" '
                	BEGIN {
                		pattern = version
                		gsub(/\./, "\\.", pattern)

                		# Bounded on both sides, so that 1.2.3 answers neither for
                		# 1.2.30 nor for 1.2.3-rc.1 — a hyphen starts a different
                		# version, and the release for it was published already.
                		pattern = "(^|[^0-9.])" pattern "([^0-9.-]|$)"
                	}

                	/^#+[[:space:]]/ {
                		match($0, /^#+/)
                		level = RLENGTH

                		# A deeper heading belongs to the section — `### Fixed`
                		# under `## 1.2.3` is where the entries are — so only one
                		# at the same level or above it ends the section.
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
                ' "$CHANGELOG" >notes.md

                flags=(--title "$version")
                created=()

                case "$TAG" in
                	*-*) flags+=(--prerelease) ;;
                esac

                if test -s notes.md; then
                	flags+=(--notes-file notes.md)
                else
                	echo "::warning::$CHANGELOG says nothing about $version, falling back to the commit summary"

                	# Only a release being created can have its notes generated,
                	# so a rerun that lands here leaves the ones already there.
                	created+=(--generate-notes)
                fi

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
