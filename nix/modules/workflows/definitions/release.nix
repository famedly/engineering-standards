{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
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
        { uses = "actions/checkout@${av.checkout}"; }
        {
          uses = "softprops/action-gh-release@${av.ghRelease}";
          with_ = {
            draft = config.draft;
            generate_release_notes = true;
            prerelease = false;
          };
        }
      ];
    };
  };
}
