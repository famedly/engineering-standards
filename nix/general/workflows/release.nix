## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

{
  config,
  lib,
  flake-parts-lib,
  standardsLib,
  ...
}:
let
  inherit (config.famedly.standards.ci) steps;
  inherit (standardsLib) script breakingChangeMarks;

  issuer = "https://token.actions.githubusercontent.com";

  # Substituted from the environment further down rather than written as
  # `${{ }}`, so a tag someone chose never reaches the shell as syntax.
  identity =
    image: "https://github.com/@REPOSITORY@/.github/workflows/${image.workflow}@refs/tags/@TAG@";
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.release = {
      enable = lib.mkEnableOption ''
        publishing a GitHub release for every version tag

        A tag says a version exists; the release says what changed in it,
        what of that breaks anyone depending on it, and whether the version
        says so too
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

      signedImages = lib.mkOption {
        description = ''
          Images a version tag publishes, which its release notes then say
          how to check.

          Set by the modules that publish them: a keyless signature names
          the workflow that made it, and only they know which one that is.
        '';

        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              reference = lib.mkOption {
                description = "The image with its registry, without a tag.";
                type = lib.types.str;
                example = "registry.famedly.net/docker-releases/famedly-control-client";
              };

              workflow = lib.mkOption {
                description = "File name of the workflow that publishes it.";
                type = lib.types.str;
                example = "dart-web.yml";
              };
            };
          }
        );

        default = [ ];
      };
    };
  });

  config.perSystem =
    { config, ... }:
    let
      cfg = config.famedly.standards.release;
      inherit (config.famedly.standards.breakingChanges) enforce;
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

          env.TAG = "\${{ github.ref_name }}";

          # The commits since the previous release, and the tag that marks it.
          steps = steps.withHistory steps.checkout ++ [
            {
              name = "Find the breaking changes since the previous release";

              run = script [
                breakingChangeMarks
                ''
                  # The latest release before this one, prereleases aside, so that
                  # a release candidate is compared with the last real release.
                  previous=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' "$TAG^" 2>/dev/null || true)
                  echo "$previous" >previous

                  range=$TAG
                  if test -n "$previous"; then
                  	range="$previous..$TAG"
                  fi

                  : >breaking.md

                  for commit in $(git rev-list --no-merges --reverse "$range"); do
                  	subject=$(git show -s --format=%s "$commit")
                  	body=$(git show -s --format=%b "$commit")

                  	# Either mark will do here, the commit check is where a
                  	# missing one is pointed out.
                  	if has_bang "$subject" || has_footer "$body"; then
                  		echo "- $subject ($(git rev-parse --short "$commit"))" >>breaking.md

                  		# The migration notes: from the footer to the end of the
                  		# message, indented to stay in the list item, without the
                  		# Co-authored-by and Signed-off-by lines.
                  		awk -v footer="$breaking_footer" '
                  			$0 ~ footer { notes = 1; print "" }
                  			notes && !/-by: / { print "  " $0 }
                  		' <<<"$body" >>breaking.md
                  	fi
                  done
                ''
              ];
            }

            {
              name = "Publish the release";

              env = {
                GH_TOKEN = "\${{ github.token }}";
                CHANGELOG = cfg.changelog;
              };

              run = script (
                [
                  ''
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

                    if test -s notes.md; then
                    	described=1
                    else
                    	echo "::warning::$CHANGELOG says nothing about $version, falling back to the commit summary"

                    	# The summary `--generate-notes` writes, asked for here
                    	# instead: that flag fills the whole body and only on
                    	# creation, which leaves nowhere to add anything to. A
                    	# summary is not worth failing a release for, so a refusal
                    	# leaves whatever follows standing on its own — written
                    	# beside the notes, so that it is a refusal and not an
                    	# emptying of them.
                    	described=
                    	if gh api "repos/$GITHUB_REPOSITORY/releases/generate-notes" \
                    		-f tag_name="$TAG" --jq .body >summary.md && test -s summary.md; then
                    		mv summary.md notes.md
                    		described=1
                    	fi
                    fi
                  ''

                  ''
                    # Every release says whether it breaks anything. A changelog
                    # that already does is left to say it in its own words.
                    if ! grep -qE '^#+[[:space:]]+Breaking changes and migration' notes.md; then
                    	{
                    		printf '\n## Breaking changes and migration\n\n'

                    		if test -s breaking.md; then
                    			cat breaking.md
                    		else
                    			echo 'None.'
                    		fi
                    	} >>notes.md
                    fi
                  ''
                ]
                ++ lib.optional (cfg.signedImages != [ ]) ''
                  # A release is where someone arrives who was sent a version,
                  # and the check they would want asks for an identity they have
                  # no way to guess. Written out per release because it names the
                  # tag, which is the part that makes it worth pasting.
                  appendix=$(cat <<'EOF'
                  ## Verifying this release

                  Each image is signed with the identity of the workflow that built it rather
                  than with a key, so what a check establishes is which build produced the image.
                  It reads the signature from the registry beside the image, and needs
                  credentials for it.

                  ${
                    lib.concatMapStrings (image: ''
                      ```bash
                      cosign verify \
                        --certificate-identity ${identity image} \
                        --certificate-oidc-issuer ${issuer} \
                        ${image.reference}:@TAG@
                      ```

                    '') cfg.signedImages
                  }The `.spdx.json` files attached below name what each image and the application
                  were built from, for a reader who has no such credentials. The same documents
                  are signed onto the images, and can be read from there rather than from this
                  page:

                  ${
                    lib.concatMapStrings (image: ''
                      ```bash
                      cosign verify-attestation --type spdxjson \
                        --certificate-identity ${identity image} \
                        --certificate-oidc-issuer ${issuer} \
                        ${image.reference}:@TAG@ \
                        | jq -r .payload | base64 -d | jq .predicate
                      ```

                    '') cfg.signedImages
                  }What a tag carries is the document for the application's own packages. Each
                  architecture's image carries the one describing itself, signed onto the digest
                  that image was pushed under.
                  EOF
                  )

                  # Both substituted rather than interpolated, so that neither a
                  # repository name nor a tag reaches the shell as anything but a
                  # value.
                  appendix=''${appendix//@REPOSITORY@/$GITHUB_REPOSITORY}

                  printf '\n%s\n' "''${appendix//@TAG@/$TAG}" >>notes.md
                ''
                ++ [
                  ''
                    flags=(--title "$version")

                    # Everything semver spells with a hyphen is a prerelease.
                    case "$TAG" in
                    	*-*) flags+=(--prerelease) ;;
                    esac

                    # Created or edited, so that a rerun finishes the job instead
                    # of failing on what the first attempt managed.
                    if gh release view "$TAG" >/dev/null 2>&1; then
                    	# Whatever a run before this one found to say about the
                    	# version outlasts a rerun that found nothing, which would
                    	# otherwise write over it with the little it has.
                    	if test -n "$described"; then
                    		flags+=(--notes-file notes.md)
                    	fi

                    	gh release edit "$TAG" "''${flags[@]}"
                    else
                    	gh release create "$TAG" --verify-tag --notes-file notes.md "''${flags[@]}"
                    fi
                  ''
                ]
              );
            }

            {
              # After publishing rather than before, so that a version that
              # hides a break still tells its readers about it.
              name = "Check that the version signals its breaking changes";

              env.LEVEL = if enforce then "error" else "warning";

              run = ''
                previous=$(cat previous)

                if ! test -s breaking.md || test -z "$previous"; then
                	echo "Nothing breaking since the previous release, or there is none"
                	exit 0
                fi

                # v1.2.3 and v1.2.3-rc.1 both read as major 1 and minor 2.
                IFS=. read -r old_major old_minor _ <<<"''${previous#v}"
                IFS=. read -r new_major new_minor _ <<<"''${TAG#v}"

                # From 1.0.0 on a break raises the major version, below it the
                # minor one.
                if ((old_major > 0)); then
                	signalled=$((new_major > old_major))
                else
                	signalled=$((new_major > 0 || new_minor > old_minor))
                fi

                if ((signalled)); then
                	echo "$TAG raises the version enough for its breaking changes"
                	exit 0
                fi

                echo "::$LEVEL::$TAG breaks what $previous offered, but does not raise the version enough to say so"
                cat breaking.md

                if [[ $LEVEL == error ]]; then
                	exit 1
                fi
              '';
            }
          ];
        };
      };
    };
}
