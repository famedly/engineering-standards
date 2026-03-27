{
  config,
  lib,
  inputs,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib)
    ghExpr
    mkNixNushellStep
    nushellShell
    ;
  nixpkgsRev = inputs.nixpkgs.rev;
in
{
  options.teams = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Teams input for the OpenPGP policy workflow (JSON array).";
    example = ''["backend", "frontend"]'';
  };

  config.definition = {
    name = "Regenerate OpenPGP Policy";
    on = {
      schedule = [ { cron = "0 6 * * 1"; } ];
      workflowDispatch = { };
    };
    jobs.regenerate-policy = {
      runsOn = "ubuntu-latest";
      permissions = {
        contents = "read";
        pull-requests = "write";
      };
      steps = [
        {
          uses = "actions/checkout@${av.checkout}";
          with_ = {
            repository = "famedly/openpgp-policy";
            token = ghExpr "github.token";
            sparse-checkout = "openpgp-policy.toml\nusers.yml";
          };
        }
        {
          uses = "cachix/install-nix-action@${av.installNix}";
          with_.extra_nix_config = "experimental-features = nix-command flakes";
        }
        (mkNixNushellStep nixpkgsRev)
        {
          name = "Generate Policy";
          shell = nushellShell;
          run = ''
            rm openpgp-policy.toml
            let users = open users.yml | get users | transpose email fingerprint
            $users | par-each {|user| sq wkd get $user.email }
            let role_overrides = open users.yml | get teams | transpose team users | filter {|it| $it.team in ${config.teams} } | get users | reduce {|it, acc| $acc | merge $it }
            $users | each {|user|
            	if ($role_overrides | get -i $user.email) == null {
            		sq-git policy authorize --committer $user.email $user.fingerprint
            	} else if ($role_overrides | get -i $user.email) == "project-maintainer" {
            		sq-git policy authorize --project-maintainer $user.email $user.fingerprint
            	} else if ($role_overrides | get -i $user.email) == "release-manager" {
            		sq-git policy authorize --release-manager $user.email $user.fingerprint
            	}
            }
            echo "Successfully regenerated openpgp-policy.toml"
          '';
        }
        {
          name = "Diff Policy";
          run = ''
            echo "POLICY_CHANGED=$(git diff --exit-code openpgp-policy.toml && echo true || echo false )" >> $GITHUB_ENV
          '';
        }
        {
          name = "Commit and create pull request";
          if_ = "env.POLICY_CHANGED == 'true'";
          env.GH_TOKEN = ghExpr "github.token";
          run = ''
            git switch --create openpgp-policy-$(date --iso-8601)
            git add openpgp-policy.toml
            git commit -m 'chore: Update openpgp-policy.toml'
            gh pr create --fill
          '';
        }
      ];
    };
  };
}
