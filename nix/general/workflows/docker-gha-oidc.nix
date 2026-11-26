## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, flake-parts-lib, ... }:
let
  # Instead of `docker login` or `podman login` (which write the token to
  # a config file), install a credential helper. Docker, podman, skopeo and
  # buildah invoke it on demand and it mints a fresh OIDC token each time,
  # so nothing is persisted and token expiry during long jobs is a non-issue.
  step = {
    name = "Install OIDC credential helper for registry.famedly.net";
    run = ''
      set -euo pipefail

      bin="$RUNNER_TEMP/bin/docker-credential-gha-oidc"
      mkdir --parents "$(dirname "$bin")"
      cat >"$bin" <<'EOF'
      ${builtins.readFile ./docker-credential-gha-oidc.sh}EOF
      ${builtins.readFile ./docker-gha-oidc-configure.sh}'';
  };

  jobModule = { config, ... }: {
    options.docker-gha-oidc = lib.mkOption {
      description = ''
        Authenticate the job's docker, podman, skopeo and buildah against
        registry.famedly.net with the job's GitHub Actions OIDC token.

        Installs the `docker-credential-gha-oidc` credential helper as the
        job's first step, registers it in Docker's `config.json` and in the
        containers tools' `REGISTRY_AUTH_FILE` (the one already set, or a new
        one) and grants the job `id-token: write` (plus `contents: read`,
        unless set otherwise, since naming any permission revokes the rest).

        GitHub never grants `id-token: write` to pull requests from forks,
        so such jobs should be skipped for them, e.g. with
        `if_ = "github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository";`.

        E.g.:

        ```nix
        perSystem.githubActions.workflows.foo.jobs.publish = {
          docker-gha-oidc = true;
          steps = [ ... ];
        };
        ```
      '';
      type = lib.types.bool;
      default = false;
    };

    config = lib.mkIf config.docker-gha-oidc {
      permissions = {
        # Required for the runner to expose
        # ACTIONS_ID_TOKEN_REQUEST_URL/_TOKEN.
        id-token = "write";
        contents = lib.mkDefault "read";
      };

      steps = lib.mkBefore [ step ];
    };
  };
in
{
  # Extends the job type of github-actions-nix: submodule types declared
  # twice merge their modules.
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.githubActions.workflows = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.jobs = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule jobModule); };
        }
      );
    };
  };
}
