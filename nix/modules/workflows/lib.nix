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

  nushellShell = "nu --no-config-file --no-history {0}";

  mkNixNushellStep = nixpkgsRev: {
    name = "Install nushell";
    run = "nix profile install github:NixOS/nixpkgs/${nixpkgsRev}#nushell";
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
          "CRATE_REGISTRY_SSH_PRIVKEY"
          "FRONTEND_REVIEW_APP_SSH_KEY"
          "GITHUB_TOKEN"
          "OCI_REGISTRY_PASSWORD"
        ];
  };
}
