{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghExpr;
in
{
  options.draft = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Create releases as drafts.";
  };

  config.definition = {
    name = "GitHub Release";
    on.push.tags = [ "v[0-9]+.[0-9]+.[0-9]+" ];
    permissions.contents = "write";
    jobs.release = {
      runsOn = "ubuntu-latest";
      if_ = "startsWith(github.ref, 'refs/tags/')";
      steps = [
        { uses = av."actions/checkout"; }
        {
          name = "Create GitHub Release";
          env.GH_TOKEN = ghExpr "github.token";
          run =
            "gh release create ${ghExpr "github.ref_name"} --generate-notes"
            + lib.optionalString config.draft " --draft"
            + " --verify-tag";
        }
      ];
    };
  };
}
