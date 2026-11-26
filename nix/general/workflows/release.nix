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
  inherit (standardsLib) script;

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
                  }The `.cdx.json` files attached below are CycloneDX documents naming what each
                  image and the application were built from, for a reader who has no such
                  credentials. The same documents are signed onto the images, and can be read
                  from there rather than from this page:

                  ${
                    lib.concatMapStrings (image: ''
                      ```bash
                      cosign verify-attestation --type cyclonedx \
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
          ];
        };
      };
    };
}
