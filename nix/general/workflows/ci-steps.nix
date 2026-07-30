{ config, lib, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
  inherit (config.famedly.standards.ci) steps;
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

            E.g.:

            ```nix
            steps.publishImages {
              reference = "registry.famedly.net/docker-releases/foo";
              tag = "latest";
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
