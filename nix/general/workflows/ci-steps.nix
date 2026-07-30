{ config, lib, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;

  script = import ../../lib/compose-script.nix { inherit lib; };
in
{
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

            Each image is described in an SPDX document before it is pushed.
            `lockfile` adds one for the packages the application was built
            from, which a compiled bundle no longer names.

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
              # A compiled bundle no longer names its packages; this does.
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
            ${lib.concatMapStringsSep "\n" (architecture: ''
              skopeo copy --dest-creds "$REGISTRY_USER:$REGISTRY_PASSWORD" \
              	docker-archive:images/image-${architecture}.tar \
              	"docker://$IMAGE:$TAG-${architecture}"
            '') architectures}
            manifest-tool --username "$REGISTRY_USER" --password "$REGISTRY_PASSWORD" \
            	push from-args \
            	--platforms ${lib.concatMapStringsSep "," (architecture: "linux/${architecture}") architectures} \
            	--template "$IMAGE:$TAG-ARCH" \
            	--target "$IMAGE:$TAG"
          '';
        }
      ];
  };
}
