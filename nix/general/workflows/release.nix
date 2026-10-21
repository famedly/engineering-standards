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
      # Kept only to say where it went: `mkRemovedOptionModule` reports through
      # `assertions`, which a flake-parts `perSystem` does not have.
      changelog = lib.mkOption {
        description = "Removed, the release notes are rendered from the commits.";
        type = lib.types.unspecified;
        visible = false;
      };

      enable = lib.mkEnableOption ''
        publishing a GitHub release for every version tag

        A tag says a version exists; the release says what changed in it. The
        notes are rendered by git-cliff from the commits since the last
        version, and a version whose bump is too small for the breaking
        changes it contains gets no release at all
      '';

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
    { config, options, ... }:
    let
      cfg = config.famedly.standards.release;
    in
    lib.mkIf cfg.enable {
      githubActions.workflows.release =
        lib.throwIf options.famedly.standards.release.changelog.isDefined
          ''
            famedly.standards.release.changelog has been removed: release notes
            are rendered from the commits by git-cliff, see
            famedly.standards.changelog. Move what the file said into the
            commits' messages, and remove the option.
          ''
          {
            name = "Publish a release for the tag";

            on.push.tags = [ "v*" ];

            jobs.release = {
              runsOn = "ubuntu-latest";

              timeoutMinutes = 10;

              # The only write this workflow makes.
              permissions.contents = "write";

              # The commits since the last version are what the notes are made of,
              # and a shallow clone has neither them nor the tag that marks it.
              steps = steps.withHistory (steps.checkout ++ steps.installNix) ++ [
                {
                  name = "Render the release notes";

                  # git-cliff alone, from the project's own nixpkgs: the devshell
                  # would bring the whole toolchain along for it.
                  shell = "nix shell --inputs-from . nixpkgs#git-cliff --command bash -e {0}";

                  env.TAG = "\${{ github.ref_name }}";

                  # Fails, and so publishes nothing, when a breaking change is
                  # marked only half or the version is too small for one. The tag
                  # is pushed by then, and has to be deleted and set again.
                  run = ''
                    case "$TAG" in
                    	# Not a version the next one counts from, so not a tag
                    	# git-cliff knows either: everything since the last final
                    	# version, under this one's name.
                    	*-*) git cliff --offline --unreleased --tag "$TAG" --strip all ;;
                    	*) git cliff --offline --current --strip all ;;
                    esac >notes.md
                  '';
                }

                {
                  name = "Publish the release";

                  env = {
                    GH_TOKEN = "\${{ github.token }}";
                    TAG = "\${{ github.ref_name }}";
                  };

                  run = script (
                    lib.optional (cfg.signedImages != [ ]) ''
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
                        flags=(--title "''${TAG#v}" --notes-file notes.md)

                        # Everything semver spells with a hyphen is a prerelease.
                        case "$TAG" in
                        	*-*) flags+=(--prerelease) ;;
                        esac

                        # Created or edited, so that a rerun finishes the job instead
                        # of failing on what the first attempt managed.
                        if gh release view "$TAG" >/dev/null 2>&1; then
                        	gh release edit "$TAG" "''${flags[@]}"
                        else
                        	gh release create "$TAG" --verify-tag "''${flags[@]}"
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
