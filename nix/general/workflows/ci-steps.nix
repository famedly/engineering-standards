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

      Null to begin with, deliberately: a gate switched on before anyone has
      seen a single report either blocks every release on the day it lands or
      teaches everyone to ignore it. Read the reports first, then set this.
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

        setup = lib.mkOption {
          description = ''
            The steps every workflow of ours starts with: check out the
            repository and install nix.

            Since the toolchain comes from the devshell, there is deliberately
            no language-specific setup action here.
          '';
          type = lib.types.listOf lib.types.attrs;
          readOnly = true;
        };

        privateDependencies = lib.mkOption {
          description = ''
            Grant the runner read access to our private repositories, for
            projects that depend on them over SSH.

            Expects a deploy key in the `CI_SSH_PRIVATE_KEY` secret. We
            configure git rather than an ssh-agent, because an agent would not
            survive the step it was started in.
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

            Each image is described in an SPDX document before it is pushed, and
            a `lockfile` adds one for what the application was built from — what
            the image itself holds says nothing about that, since a compiled
            bundle carries no manifest.

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

        # Without this the action leaves the token in `.git/config`, where
        # every later step can read it — including the code generators and
        # package scripts a build runs. Nothing of ours talks to the remote
        # after the checkout; what needs the API takes the token as an
        # environment variable of the one step that needs it.
        with_.persist-credentials = false;
      }
    ];
    installNix = [ { uses = allowed-actions."cachix/install-nix-action".uses; } ];

    setup = steps.checkout ++ steps.installNix;

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
          # Written from the archives rather than from the recipe, so it
          # describes what is about to be pushed and not what was meant to be.
          name = "Describe what the images hold";

          shell = "nix shell --inputs-from . nixpkgs#syft --command bash -e {0}";

          env = {
            IMAGE = reference;
            TAG = tag;
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
              	--output spdx-json=sboms/image-${architecture}.spdx.json
            '') architectures
            ++ lib.optional (lockfile != null) ''
              # The bundle in the image carries no trace of the packages it was
              # compiled from, so the lockfile speaks for them.
              syft scan file:${lockfile} \
              	--source-name "$IMAGE" --source-version "$TAG" \
              	--output spdx-json=sboms/source.spdx.json
            ''
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
          # Held against the documents just written rather than against the
          # archives again: whatever the scanner has to say, it says it about
          # the same list of packages that ships with the image.
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

              for sbom in sboms/*.spdx.json; do
              	name="$(basename "$sbom" .spdx.json)"

              	# Into a file rather than through a pipe, so the summary below
              	# is written even when the report is the reason this step fails.
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

            # A digest is the hash of the manifest bytes, and the list is the
            # one thing pushed here that arrived without one of its own. Read
            # back rather than parsed out of the push, so what gets signed
            # below is what the registry now serves under this tag.
            skopeo inspect --creds "$REGISTRY_USER:$REGISTRY_PASSWORD" \
            	--raw "docker://$IMAGE:$TAG" \
            	| sha256sum | cut -d' ' -f1 | sed 's/^/sha256:/' >digests/list
          '';
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
                # Keyless, so there is no key of ours to hold, leak or rotate:
                # the signature is bound to this workflow's identity, which
                # GitHub vouches for over OIDC. The price is a public record in
                # the transparency log, naming the image and its digest.
                printf '%s' "$REGISTRY_PASSWORD" \
                	| cosign login "''${IMAGE%%/*}" \
                		--username "$REGISTRY_USER" --password-stdin
              ''
            ]
            ++ map (architecture: ''
              digest="$(cat digests/${architecture})"

              cosign sign --yes "$IMAGE@$digest"

              cosign attest --yes --type spdxjson \
              	--predicate sboms/image-${architecture}.spdx.json \
              	"$IMAGE@$digest"
            '') architectures
            ++ [
              ''
                # The list is what anyone pulls by tag, so it is what a policy
                # will be checking.
                list="$(cat digests/list)"

                cosign sign --yes "$IMAGE@$list"
              ''
            ]
            ++ lib.optional (lockfile != null) ''
              cosign attest --yes --type spdxjson \
              	--predicate sboms/source.spdx.json \
              	"$IMAGE@$list"
            ''
          );
        }
      ];
  };
}
