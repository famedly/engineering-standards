{ config, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;

  ociRegistryURLs = {
    snapshots = "registry.famedly.net/docker-nightly";
    releases = "registry.famedly.net/docker-releases";
    openSourceReleases = "registry.famedly.net/docker-oss";
  };
in
{
  perSystem.githubActions.workflows.rust-test = {
    name = "Rust workflow";

    on = {
      push = {
        branches = [ "main" ];
        tags = [ "*" ];
      };

      pullRequest = {
        branches = [ "*" ];
        types = [
          "opened"
          "reopened"
          "synchronize"
          "ready_for_review"
        ];
      };
    };

    concurrency = {
      group = "\${{ github.workflow }}-\${{ github.ref }}";
      cancelInProgress = true;
    };

    env.CARGO_TERM_COLOR = "always";

    # TODO(tlater): Perhaps don't install nushell in the default rust
    # devshell; we might want a bespoke shell for this workflow?
    defaults.run.shell = "nix develop .#rust --command nu {0}";

    jobs.rust-tests = {
      if_ = "github.event.pull_request.draft == false";
      runs_on = "ubuntu-latest-4core";

      steps = [
        { uses = allowed-actions."cachix/install-nix-action".uses; }

        # TODO: We should hard-code the shipyard ssh cert, this
        # breaks ssh's security model
        #
        # I'm implementing it like this because our existing
        # workflow does this, don't eat me. I've pointed it out
        # before, and basically been told that this is more
        # convenient and that we don't want all our workflows to
        # fail just because the shipyard cert changed.
        #
        # Maybe after we've centralized things the
        # single-repo-update-to-fix-everything will make the
        # overhead of a potential ssh key update low enough that we
        # can actually do this correctly.
        {
          name = "Setup SSH Keys and known_hosts";
          run = ''
            mkdir ~/.ssh

            # Start the ssh agent
            ^ssh-agent -c
              | lines
              | first 2
              | parse "setenv {name} {value};"
              | transpose -r
              | into record
              | load-env

            # Add the shipyard SSH certificate
            ssh-keyscan git.shipyard.rs | save -f ~/.ssh/known_hosts

            # Add our secret key to the ssh agent
            #
            # TODO: It appears that this has been nonfuctional since
            # at least November 2025 , with the failure ignored by a
            # convenient `|| true`... We should probably just omit
            # the entire step?
            try {
              (r#'${
                # Ugly hack to avoid triple backtick - nix and
                # nushell escapes are fighting a lil' here
                "\${{ secrets.CRATE_REGISTRY_SSH_PRIVKEY }}"
              }'# | ssh-add -)
            }

            # Persist the ssh agent env variables
            [
              $'SSH_AUTH_SOCK=($env.SSH_AUTH_SOCK)'
              $'SSH_AGENT_PID=($env.SSH_AGENT_PID)'
            ] | str join "\n" | save --append $env.GITHUB_ENV
          '';
        }

        {
          name = "Resolve OCI registry to push to";
          run = ''
            let registry = match $env.GITHUB_REF_TYPE {
              "branch" => '${ociRegistryURLs.snapshots}'
              "tag" if $env.GITHUB_REF_NAME =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' => '${
                if config.famedly.standards.isOpenSource then
                  ociRegistryURLs.openSourceReleases
                else
                  ociRegistryURLs.releases
              }'
              "tag" => '${ociRegistryURLs.snapshots}'
            }

            $'OCI_REGISTRY=($registry)' | save --append $env.GITHUB_ENV
          '';
        }

        {
          name = "Log into registry \${{ env.OCI_REGISTRY }}";
          uses = allowed-actions."docker/login-action";
          if_ = "env.OCI_REGISTRY != null";
          with_ = {
            registry = "\${{ env.OCI_REGISTRY }}";
            username = "\${{ variables.ociRegistryUser }}";
            password = "\${{ secrets.OCI_REGISTRY_PASSWORD || secrets.GITHUB_TOKEN }}";
          };
        }

        {
          name = "Configure cargo";

          # We assume the default cargo home of `~/.cargo`; This could
          # theoretically go wrong on a user switch, or some weird
          # toolchain overrides.
          #
          # *Perhaps* we should use the `CARGO_HOME` variable in
          # `$env.GITHUB_ENV` to force a consistent location instead,
          # but we don't think it can actually break.
          run = ''
            {
              net: {
                git-fetch-with-cli: true
              }

              $"registries.($env.CRATE_REGISTRY_NAME)" = {
                index: $env.CRATE_REGISTRY_INDEX_URL
              }
            } | to toml | save -f ~/.cargo/config.toml
          '';
        }

        { uses = allowed-actions."actions/checkout".uses; }
        { uses = allowed-actions."Swatinem/rust-cache".uses; }

        {
          name = "Run rust tests";
          # TODO(tlater): Allow modifying the args with an option
          run = "cargo llvm-cov nextest --profile ci --workspace --lcov --output-path lcov.info";
        }

        # TODO(tlater): Add support for doctests - might need
        # toolchain modifications, given the nightly thing.
        #
        # {
        #   name = "Run doctests";
        #   run = "cargo +\${NIGHTLY_VERSION} test --doc --workspace --verbose ${test_args}";
        # }

        {
          uses = allowed-actions."codecov/codecov-action".uses;
          with_ = {
            token = "\${{ secrets.CODECOV_TOKEN }}";
            files = "lcov.info";
          };
        }

        {
          uses = allowed-actions."codecov/test-results-action".uses;
          with_.token = "\${{ secrets.CODECOV_TOKEN }}";
        }
      ];
    };
  };
}
