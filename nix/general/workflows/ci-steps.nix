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
      };
    };
  };

  config.famedly.standards.ci.steps = {
    checkout = [ { uses = allowed-actions."actions/checkout".uses; } ];
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

    devshell = "nix develop .#standards --command bash {0}";
  };
}
