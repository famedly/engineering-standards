## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;

  script = import ../../lib/compose-script.nix { inherit lib; };
in
{
  options.famedly.standards.ci.advisories.failOn = lib.mkOption {
    description = ''
      Severity at which a known vulnerability in a published image stops the
      run, or `null` to only report what was found.

      Null until the reports have been read: a gate nobody has calibrated
      either blocks every release or gets ignored.
    '';

    type = lib.types.nullOr (
      lib.types.enum [
        "low"
        "medium"
        "high"
        "critical"
      ]
    );

    default = null;
  };

  options.famedly.standards.ci.steps = lib.mkOption {
    description = ''
      Workflow steps shared between our GitHub workflows.

      Downstream projects should compose their workflows from these instead of
      spelling out action refs themselves, so that action versions stay
      reviewed in one place and the devshell plumbing stays consistent.

      E.g.:

      ```nix
      { config, ... }:
      let
        inherit (config.famedly.standards.ci) steps;
      in
      {
        perSystem.githubActions.workflows.foo.jobs.bar.steps = steps.setup ++ [
          {
            name = "Do the thing";
            shell = steps.devshell;
            run = "the-thing";
          }
        ];
      }
      ```
    '';
    readOnly = true;

    type = lib.types.submodule {
      options = {
        checkout = lib.mkOption {
          description = "Check out the repository.";
          type = lib.types.listOf lib.types.attrs;
          readOnly = true;
        };

        installNix = lib.mkOption {
          description = "Make `nix` available on the runner.";
          type = lib.types.listOf lib.types.attrs;
          readOnly = true;
        };

        freeDiskSpace = lib.mkOption {
          description = ''
            Delete the language toolchains GitHub preinstalls on its runners.

            A runner has around 20 GB free, and a devshell that brings a Flutter
            SDK and two Rust toolchains does not fit beside all of that. Builds
            fail with "No space left on device" halfway through.

            Nothing of ours uses any of it: our toolchain comes from the
            devshell, which is the reason we can throw it away wholesale.
          '';
          type = lib.types.listOf lib.types.attrs;
          readOnly = true;
        };

        setup = lib.mkOption {
          description = ''
            The steps every workflow of ours starts with: make room on the
            runner, check out the repository and install nix.

            Since the toolchain comes from the devshell, there is deliberately
            no language-specific setup action here.
          '';
          type = lib.types.listOf lib.types.attrs;
          readOnly = true;
        };

        withHistory = lib.mkOption {
          description = ''
            Deepen the checkout in a list of steps, for a job that reads the
            repository's history rather than only the files at its head.

            A shallow clone carries neither the tags nor the commits leading up
            to them, and the checkout takes the token with it when it leaves, so
            a job that needs the history has to ask for it there and then.

            E.g. `steps.withHistory steps.setup`.
          '';
          type = lib.types.functionTo (lib.types.listOf lib.types.attrs);
          readOnly = true;
        };

        privateDependencies = lib.mkOption {
          description = ''
            Grant the runner read access to our private repositories, for
            projects that depend on them.

            Expects a deploy key in the `CI_SSH_PRIVATE_KEY` secret. We
            configure git rather than an ssh-agent, because an agent would not
            survive the step it was started in.

            A dependency may name its repository over either protocol: the key
            answers for both.
          '';
          type = lib.types.listOf lib.types.attrs;
          readOnly = true;
        };

        devshell = lib.mkOption {
          description = ''
            A step `shell` that runs the step's `run` script inside the
            projects' `standards` devshell.
          '';
          type = lib.types.str;
          readOnly = true;
        };

        publishImages = lib.mkOption {
          description = ''
            Steps that push the per-architecture image archives a build left
            behind, and the manifest list that ties them together.

            Expects one `image-<architecture>` artefact per architecture, each
            holding an `image-<architecture>.tar`, and credentials in the
            `REGISTRY_USER` variable and the `registry_password` secret.

            Each image is described in a CycloneDX document before it is
            pushed. `lockfile` adds one for the packages the application was
            built from, which a compiled bundle no longer names; that one is
            named after the image with `-source` appended, so the two documents
            cannot be mistaken for versions of each other.

            Once the registry has the images, each document is told what it
            describes: the digest of the artefact, the repository it was built
            from and the run that built it. A digest is the one name for an
            image that cannot drift, and it is known no earlier than this.

            `release` attaches those documents to the GitHub release for a
            version tag as well, named after the image they describe, for
            whoever asks what a released version shipped without holding
            credentials for the registry. Requires `contents: write` on the
            job.

            It also sends them to the Dependency-Track instance named in the
            `DEPENDENCY_TRACK_URL` variable, authenticated by the
            `dependency_track_api_key` secret, which answers the question the
            other way round: a component became a problem today, and which
            released version holds it. Where the variable is unset, that step
            is skipped. The key needs `BOM_UPLOAD`,
            `PROJECT_CREATION_UPLOAD`, `VIEW_PORTFOLIO` and
            `PORTFOLIO_MANAGEMENT_CREATE` — enough to add a version and carry
            over what was decided about the one before it, and not enough to
            change or remove anything already recorded.

            E.g.:

            ```nix
            steps.publishImages {
              reference = "registry.famedly.net/docker-releases/foo";
              tag = "latest";
              lockfile = "pubspec.lock";
            }
            ```
          '';
          type = lib.types.functionTo (lib.types.listOf lib.types.attrs);
          readOnly = true;
        };
      };
    };
  };

  config.famedly.standards.ci.steps = {
    checkout = [
      {
        uses = allowed-actions."actions/checkout".uses;

        # Otherwise the token stays in `.git/config` for every later step to
        # read, package scripts included. What needs the API takes it as an
        # environment variable instead.
        with_.persist-credentials = false;
      }
    ];
    installNix = [ { uses = allowed-actions."cachix/install-nix-action".uses; } ];

    freeDiskSpace = [
      {
        name = "Free up disk space";
        run = ''
          sudo rm -rf /usr/share/dotnet /usr/share/swift /usr/local/lib/android \
          	/opt/ghc /opt/hostedtoolcache
          df -h /
        '';
      }
    ];

    setup = steps.freeDiskSpace ++ steps.checkout ++ steps.installNix;

    withHistory = map (
      step:
      if (step.uses or null) == allowed-actions."actions/checkout".uses then
        lib.recursiveUpdate step { with_.fetch-depth = 0; }
      else
        step
    );

    privateDependencies = [
      {
        name = "Grant access to private famedly repositories";
        env.SSH_PRIVATE_KEY = "\${{ secrets.CI_SSH_PRIVATE_KEY }}";
        run = ''
          install -d -m 700 ~/.ssh
          printf '%s\n' "$SSH_PRIVATE_KEY" >~/.ssh/famedly-ci
          chmod 600 ~/.ssh/famedly-ci

          ssh-keyscan -t rsa,ecdsa,ed25519 github.com >>~/.ssh/known_hosts

          git config --global core.sshCommand \
          	'ssh -i ~/.ssh/famedly-ci -o IdentitiesOnly=yes'

          # Dependabot reaches our repositories over HTTPS with a token, so
          # lockfiles that it is to keep up to date have to name them that way.
          # Here the key is all we have, and it only speaks SSH.
          git config --global url."git@github.com:famedly/".insteadOf \
          	'https://github.com/famedly/'
        '';
      }
    ];

    # `-e` because a custom `shell` replaces the `bash -e` GitHub runs `run`
    # scripts with, and a multi-command script that carries on after a failure
    # reports the exit status of its last command.
    devshell = "nix develop .#standards --command bash -e {0}";

    publishImages =
      {
        reference,
        tag,
        lockfile ? null,
        release ? false,
        architectures ? [
          "amd64"
          "arm64"
        ],
      }:
      [
        {
          uses = allowed-actions."actions/download-artifact".uses;

          with_ = {
            pattern = "image-*";
            path = "images";
            merge-multiple = true;
          };
        }

        {
          # From the archives rather than the recipe, so it describes what is
          # pushed.
          #
          # CycloneDX 1.6, which is a version BSI TR-03183-2 accepts and syft
          # writes. Its SPDX output stops at 2.3 where that guideline asks for
          # 3.0.1, so the format used until now could not serve the purpose the
          # documents exist for. `syft convert` still produces SPDX for whoever
          # asks in that format, and it is the only format Dependency-Track and
          # its kind ingest — the same direction from two sides.
          name = "Describe what the images hold";

          shell = "nix shell --inputs-from . nixpkgs#syft nixpkgs#jq --command bash -e {0}";

          env = {
            IMAGE = reference;
            TAG = tag;

            # Who a reader is to ask about the document, which the guidelines
            # asking for these documents all want named.
            SUPPLIER = "Famedly GmbH";
          };

          run = script (
            [
              ''
                mkdir -p sboms
              ''
            ]
            ++ map (architecture: ''
              syft scan docker-archive:images/image-${architecture}.tar \
              	--source-name "$IMAGE" --source-version "$TAG-${architecture}" \
              	--source-supplier "$SUPPLIER" \
              	--output cyclonedx-json=sboms/image-${architecture}.cdx.json
            '') architectures
            ++ lib.optional (lockfile != null) ''
              # A compiled bundle no longer names its packages; this does. Under
              # a name of its own, because the packages an application was built
              # from are not another version of the image built from them, and a
              # reader given one name for both has no way to tell them apart.
              syft scan file:${lockfile} \
              	--source-name "$IMAGE-source" --source-version "$TAG" \
              	--source-supplier "$SUPPLIER" \
              	--output cyclonedx-json=sboms/source.cdx.json

              # syft names what it read, and what it read is a lockfile. The
              # document is about the application built from that lockfile, and
              # anything sorting documents by kind reads this field to decide.
              jq '.metadata.component.type = "application"' \
              	sboms/source.cdx.json >sboms/source.cdx.json.new
              mv sboms/source.cdx.json.new sboms/source.cdx.json
            ''
            ++ [
              ''
                # syft guesses a CPE for every package it finds, and NVD entries
                # match those on vendor and product alone. A guess of
                # `tokio:tokio` therefore collects an advisory about a different
                # crate entirely, reported as critical and with no upper version
                # bound to ever release it again. PURLs carry the ecosystem, so
                # dropping the guesses loses nothing: grype reports the same
                # advisories from these documents either way.
                for sbom in sboms/*.cdx.json; do
                	jq 'del(.components[]?.cpe)' "$sbom" >"$sbom.new"
                	mv "$sbom.new" "$sbom"
                done
              ''
            ]
          );
        }

        {
          uses = allowed-actions."actions/upload-artifact".uses;

          with_ = {
            name = "sbom";
            path = "sboms";
            if-no-files-found = "error";
          };
        }

        {
          # Against the documents just written, so the report covers the
          # packages that ship.
          name = "Look for known vulnerabilities";

          shell = "nix shell --inputs-from . nixpkgs#grype --command bash -e {0}";

          run =
            let
              inherit (config.famedly.standards.ci.advisories) failOn;
            in
            ''
              mkdir -p reports

              echo '### Known vulnerabilities' >>"$GITHUB_STEP_SUMMARY"

              status=0

              for sbom in sboms/*.cdx.json; do
              	name="$(basename "$sbom" .cdx.json)"

              	# Into a file, so the summary is written even when the report
              	# is what fails this step.
              	grype "sbom:$sbom" --output table --file "reports/$name.txt" \
              		${lib.optionalString (failOn != null) "--fail-on ${failOn} "}|| status=$?

              	{
              		echo "#### $name"
              		echo '```'
              		cat "reports/$name.txt"
              		echo '```'
              	} >>"$GITHUB_STEP_SUMMARY"
              done

              exit "$status"
            '';
        }

        {
          name = "Push the images and the manifest list";

          # Pinned like everything else, since it resolves against the
          # repository's own locked nixpkgs.
          shell = "nix shell --inputs-from . nixpkgs#manifest-tool nixpkgs#skopeo --command bash -e {0}";

          env = {
            REGISTRY_USER = "\${{ vars.REGISTRY_USER }}";
            REGISTRY_PASSWORD = "\${{ secrets.registry_password }}";

            IMAGE = reference;
            TAG = tag;
          };

          run = ''
            mkdir -p digests

            ${lib.concatMapStringsSep "\n" (architecture: ''
              skopeo copy --dest-creds "$REGISTRY_USER:$REGISTRY_PASSWORD" \
              	--digestfile digests/${architecture} \
              	docker-archive:images/image-${architecture}.tar \
              	"docker://$IMAGE:$TAG-${architecture}"
            '') architectures}
            manifest-tool --username "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" \
            	push from-args \
            	--platforms ${lib.concatMapStringsSep "," (architecture: "linux/${architecture}") architectures} \
            	--template "$IMAGE:$TAG-ARCH" \
            	--target "$IMAGE:$TAG"

            # The one thing pushed here without a digest of its own. Read back
            # rather than parsed out of the push, so what is signed below is
            # what the registry serves.
            skopeo inspect --creds "$REGISTRY_USER:$REGISTRY_PASSWORD" \
            	--raw "docker://$IMAGE:$TAG" >digests/list.json

            skopeo manifest-digest digests/list.json >digests/list
          '';
        }

        {
          # syft names the image it read and stops there. What is missing is
          # the one name for an artefact that cannot drift, and the digest it
          # is built from exists only once the registry holds the image. It
          # goes in here, before anything signs, attaches or uploads a
          # document, so that every reader of one is told the same thing about
          # what it describes.
          name = "Name what the documents describe";

          shell = "nix shell --inputs-from . nixpkgs#jq --command bash -e {0}";

          env = {
            IMAGE = reference;
            TAG = tag;
          };

          run = script (
            [
              ''
                # Where it was built from, and by which run. Both hold for a
                # nightly as much as for a release, which a release page
                # would not.
                references="$(
                	jq -cn \
                		--arg repository "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY" \
                		--arg run "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                		'[{type: "vcs", url: $repository},
                		  {type: "build-system", url: $run}]'
                )"

                identify() {
                	jq --arg purl "$2" --argjson references "$references" \
                		'.metadata.component += {purl: $purl, externalReferences: $references}' \
                		"$1" >"$1.new"

                	mv "$1.new" "$1"
                }
              ''
            ]
            ++ map (architecture: ''
              identify sboms/image-${architecture}.cdx.json \
              	"pkg:oci/''${IMAGE##*/}@$(cat digests/${architecture})?repository_url=''${IMAGE%/*}&arch=${architecture}&tag=$TAG"
            '') architectures
            ++ lib.optional (lockfile != null) ''
              # No image of its own to point at: what pins the packages an
              # application was built from is the commit they were read at.
              identify sboms/source.cdx.json "pkg:github/$GITHUB_REPOSITORY@$GITHUB_SHA"
            ''
          );
        }

        {
          name = "Sign the images and attest what they hold";

          shell = "nix shell --inputs-from . nixpkgs#cosign --command bash -e {0}";

          env = {
            REGISTRY_USER = "\${{ vars.REGISTRY_USER }}";
            REGISTRY_PASSWORD = "\${{ secrets.registry_password }}";

            IMAGE = reference;
          };

          run = script (
            [
              ''
                # Keyless: no key of ours to hold or rotate, at the price of a
                # public record in the transparency log naming every image
                # signed here.
                printf '%s' "$REGISTRY_PASSWORD" \
                	| cosign login "''${IMAGE%%/*}" \
                		--username "$REGISTRY_USER" --password-stdin
              ''
            ]
            ++ map (architecture: ''
              digest="$(cat digests/${architecture})"

              cosign sign --yes "$IMAGE@$digest"

              cosign attest --yes --type cyclonedx \
              	--predicate sboms/image-${architecture}.cdx.json \
              	"$IMAGE@$digest"
            '') architectures
            ++ [
              ''
                # What anyone pulls by tag, and so what a policy checks.
                list="$(cat digests/list)"

                cosign sign --yes "$IMAGE@$list"
              ''
            ]
            ++ lib.optional (lockfile != null) ''
              cosign attest --yes --type cyclonedx \
              	--predicate sboms/source.cdx.json \
              	"$IMAGE@$list"
            ''
          );
        }
      ]
      ++ lib.optional release {
        # The registry holds the authoritative copy, attached to the digest it
        # describes. This one is for the reader who has no credentials for it
        # and no run left to download: an artefact expires, a nightly image is
        # collected, and the question of what a released version shipped
        # outlives both.
        name = "Attach the documents to the release";

        if_ = "startsWith(github.ref, 'refs/tags/')";

        env = {
          GH_TOKEN = "\${{ github.token }}";
          TAG = "\${{ github.ref_name }}";
        };

        run = ''
          # Another workflow publishes the release for this tag, and no
          # `needs` reaches across workflows. It takes seconds where this job
          # takes minutes, so waiting is precaution rather than expectation.
          for _ in $(seq 15); do
          	gh release view "$TAG" >/dev/null 2>&1 && break
          	sleep 2
          done

          if gh release view "$TAG" >/dev/null 2>&1; then
          	# A release holds one asset per file name, and a repository can
          	# publish more than one image for a tag — a second project, or a
          	# server image beside a web one. Named after the image they
          	# describe, they cannot replace each other, which would leave a
          	# document that reads as though it covered both.
          	mkdir -p assets

          	for sbom in sboms/*.cdx.json; do
          		cp "$sbom" "assets/${baseNameOf reference}-$(basename "$sbom")"
          	done

          	gh release upload "$TAG" assets/*.cdx.json --clobber
          else
          	# The images are pushed and signed by the time this runs, and the
          	# documents are attached to them. Worth saying, not worth failing.
          	echo "::warning::No release for $TAG, so its SBOM is only in the registry and this run"
          fi
        '';
      }
      ++ lib.optional release {
        # A document attached to a release answers what a version shipped, to
        # whoever thinks to look. This answers the other direction: a component
        # became a problem today, and which of the versions still in use holds
        # it. Nobody asks that of a nightly, so only released versions go in.
        #
        # Skipped where `DEPENDENCY_TRACK_URL` is unset, which is every
        # repository that has no tracker to tell.
        name = "Tell the tracker what this version holds";

        if_ = "startsWith(github.ref, 'refs/tags/') && vars.DEPENDENCY_TRACK_URL != ''";

        shell = "nix shell --inputs-from . nixpkgs#curl nixpkgs#jq --command bash -e {0}";

        env = {
          IMAGE = reference;
          TAG = "\${{ github.ref_name }}";

          DT_URL = "\${{ vars.DEPENDENCY_TRACK_URL }}";
          DT_KEY = "\${{ secrets.dependency_track_api_key }}";
        };

        run = script (
          [
            ''
              # An address typed into a settings page tends to end in a slash,
              # and every request below would carry that doubled.
              DT_URL="''${DT_URL%/}"

              api() {
              	local method="$1" path="$2"
              	shift 2

              	curl -sS --fail-with-body -X "$method" \
              		-H "X-Api-Key: $DT_KEY" -H 'Content-Type: application/json' \
              		"$DT_URL/api/$path" "$@"
              }

              # A collection project holds no components of its own and sums up
              # its children instead. Asking for one that is already there
              # answers 409, which is the ordinary case from the second release
              # onwards, so it is read back by name either way.
              collection() {
              	local name="$1" logic="$2" parent="''${3-}"

              	api PUT v1/project --data "$(
              		jq -cn --arg name "$name" --arg logic "$logic" --arg parent "$parent" \
              			'{name: $name, collectionLogic: $logic}
              			 | if $parent == "" then . else .parent = {uuid: $parent} end'
              	)" >/dev/null 2>&1 || true

              	api GET v1/project/lookup -G --data-urlencode "name=$name" | jq -r .uuid
              }

              # Carry over what was already decided about the version this one
              # follows. There is no other way to inherit it, and without this
              # every release starts its triage from nothing.
              track() {
              	local name="$1" parent="$2" sbom="$3" previous

              	# The name travels in the path here, so it is encoded for one. A
              	# first release has no version before it, and the answer to that
              	# is a sentence rather than a document.
              	previous="$(api GET "v1/project/latest/$(jq -rn --arg name "$name" '$name | @uri')" \
              		2>/dev/null | jq -r '.uuid // empty' 2>/dev/null || true)"

              	if [ -n "$previous" ]; then
              		# Everything a person could have put there by hand. The
              		# access list comes along because a clone without it is one
              		# nobody can see, should this instance ever restrict who may
              		# read what.
              		api POST "v2/projects/$previous/clone" --data "$(
              			jq -cn --arg version "$TAG" \
              				'{version: $version, version_is_latest: true,
              				  includes: ["ACL", "COMPONENTS", "FINDINGS",
              				             "FINDINGS_AUDIT_HISTORY",
              				             "POLICY_VIOLATIONS",
              				             "POLICY_VIOLATIONS_AUDIT_HISTORY",
              				             "TAGS"]}'
              		)" >/dev/null
              	fi

              	curl -sS --fail-with-body -X POST -H "X-Api-Key: $DT_KEY" \
              		-F "projectName=$name" -F "projectVersion=$TAG" \
              		-F autoCreate=true -F "parentUUID=$parent" -F isLatest=true \
              		-F "bom=@$sbom" "$DT_URL/api/v1/bom" >/dev/null
              }

              # Which registry an artefact came from is written in the document
              # itself, so what is left to name here is the short thing a
              # reader can hold in their head: the product at the top, its
              # images under that, and a line of its own for each platform. A
              # platform image is a separate artefact holding different bytes,
              # so each keeps a history of its own, and of one name only a
              # single version can be the current one.
              product="''${IMAGE##*/}"

              top="$(collection "$product" AGGREGATE_DIRECT_CHILDREN)"
              images="$(collection "$product-image" AGGREGATE_DIRECT_CHILDREN "$top")"
            ''
          ]
          ++ map (architecture: ''
            track "$product-${architecture}" \
            	"$(collection "$product-${architecture}" AGGREGATE_LATEST_VERSION_CHILDREN "$images")" \
            	sboms/image-${architecture}.cdx.json
          '') architectures
          ++ lib.optional (lockfile != null) ''
            track "$product-source" \
            	"$(collection "$product-source" AGGREGATE_LATEST_VERSION_CHILDREN "$top")" \
            	sboms/source.cdx.json
          ''
        );
      };
  };
}
