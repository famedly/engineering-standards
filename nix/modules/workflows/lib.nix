{ lib, ... }:
let
  inherit (lib.strings) toCamelCase;

  mapListToAttrs = f: list: lib.listToAttrs (map f list);
in
rec {
  # Produce a literal GitHub Actions expression: ${{ expression }}
  ghExpr = expression: "\${{ ${expression} }}";

  ghVar = name: ghExpr "vars.${name}";
  ghSecret = name: ghExpr "secrets.${name}";
  ghEnv = name: ghExpr "env.${name}";

  nixSetupStep = installNixSha: {
    uses = "cachix/install-nix-action@${installNixSha}";
    with_.extra_nix_config = "experimental-features = nix-command flakes";
  };

  mkNixInstallStep = nixpkgsRev: pkg: {
    name = "Install ${pkg}";
    run = "nix profile install github:NixOS/nixpkgs/${nixpkgsRev}#${pkg}";
  };

  nushellShell = "nu --no-config-file --no-history {0}";
  mkNixNushellStep = nixpkgsRev: mkNixInstallStep nixpkgsRev "nushell";

  mkRustPrepareStep =
    {
      shipyardToken ? null,
      additionalPackages ? "",
      registryName ? "famedly",
      registryIndexUrl ? "https://git.shipyard.rs/famedly/crate-index.git",
    }:
    {
      name = "Prepare Rust environment";
      shell = "bash";
      env = {
        ADDITIONAL_PACKAGES = additionalPackages;
        CRATE_REGISTRY_NAME = registryName;
        CRATE_REGISTRY_INDEX_URL = registryIndexUrl;
        CARGO_HOME = ".cargo";
      }
      // lib.optionalAttrs (shipyardToken != null) {
        SHIPYARD_RS_TOKEN = shipyardToken;
      };
      run = ''
        set -euo pipefail
        git config --global --add safe.directory "$(pwd)"

        if [[ "$(id -u)" -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

        if [[ -n "''${ADDITIONAL_PACKAGES:-}" ]]; then
          read -ra packages <<< "''${ADDITIONAL_PACKAGES}"
          $SUDO apt-get install -yqq --no-install-recommends "''${packages[@]}"
        fi

        mkdir -p "''${HOME}/''${CARGO_HOME}"

        if [[ -z "''${SHIPYARD_RS_TOKEN:-}" ]]; then
          export CRATE_REGISTRY_NAME="crates-io"
        else
          git config --global credential.helper store
          echo "https://famedly:''${SHIPYARD_RS_TOKEN}@git.shipyard.rs" > ~/.git-credentials
          chmod 600 ~/.git-credentials
        fi

        cat << EOF >> "''${HOME}/''${CARGO_HOME}/config.toml"
        [net]
        git-fetch-with-cli = true

        [registry]
        global-credential-providers = ["cargo:token"]
        EOF

        if [ "$CRATE_REGISTRY_NAME" != "crates-io" ]; then
          cat << EOF >> "''${HOME}/''${CARGO_HOME}/config.toml"
        [registries.''${CRATE_REGISTRY_NAME}]
        index = "''${CRATE_REGISTRY_INDEX_URL}"
        EOF

          cat << EOF >> "''${HOME}/''${CARGO_HOME}/credentials.toml"
        [registries.''${CRATE_REGISTRY_NAME}]
        token = "''${SHIPYARD_RS_TOKEN}"
        EOF
        fi

        echo "CARGO_HOME=''${HOME}/''${CARGO_HOME}" >> "$GITHUB_ENV"
        echo "CRATE_REGISTRY_NAME=''${CRATE_REGISTRY_NAME}" >> "$GITHUB_ENV"
        if [[ -n "''${CRATE_REGISTRY_INDEX_URL:-}" ]]; then
          echo "CRATE_REGISTRY_INDEX_URL=''${CRATE_REGISTRY_INDEX_URL}" >> "$GITHUB_ENV"
        fi
      '';
    };

  # Configure git HTTPS credentials so the Nix daemon can fetch private flake inputs.
  # Uses a PAT via git credential helper — works for any user (root, nixbld, runner).
  mkNixGitAuthStep =
    { token }:
    {
      name = "Configure Git auth for Nix daemon";
      shell = "bash";
      env.GH_TOKEN = token;
      run = ''
        set -euo pipefail
        if [[ -n "''${GH_TOKEN:-}" ]]; then
          sudo git config --system url."https://x-access-token:''${GH_TOKEN}@github.com/".insteadOf "https://github.com/"
        fi
      '';
    };

  mkDartPrepareStep =
    { sshKey }:
    {
      name = "Configure SSH for private dependencies";
      shell = "bash";
      env.SSH_KEY = sshKey;
      run = ''
        set -euo pipefail
        if [[ -n "''${SSH_KEY:-}" ]]; then
          mkdir -p ~/.ssh
          echo "''${SSH_KEY}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          eval $(ssh-agent)
          ssh-add ~/.ssh/id_rsa
          ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
          git config --global url."git@github.com:".insteadOf "https://github.com/"
        fi
        if command -v flutter &>/dev/null; then flutter --disable-analytics; fi
        if command -v dart &>/dev/null; then dart --disable-analytics; fi
      '';
    };

  ciConcurrency = {
    group = "${ghExpr "github.workflow"}-${ghExpr "github.ref"}";
    cancelInProgress = true;
  };

  sharedValueNames = {
    variables =
      mapListToAttrs
        (variable: {
          name = toCamelCase variable;
          value = ghVar variable;
        })
        [
          "CRATE_REGISTRY_NAME"
          "CRATE_REGISTRY_INDEX_URL"
          "OCI_REGISTRY_USER"
        ];

    secrets =
      mapListToAttrs
        (secret: {
          name = toCamelCase secret;
          value = ghSecret secret;
        })
        [
          "ADD_ISSUE_TO_PROJECT_PAT"
          "ANTHROPIC_API_KEY"
          "CACHIX_AUTH_TOKEN_FAMEDLY"
          "CACHIX_SIGNING_KEY_FAMEDLY"
          "CODECOV_TOKEN"
          "CRATE_REGISTRY_AUTH_TOKEN"
          "SHIPYARD_RS_TOKEN"
          "FRONTEND_REVIEW_APP_SSH_KEY"
          "GITHUB_TOKEN"
          "OCI_REGISTRY_PASSWORD"
        ];
  };
}
