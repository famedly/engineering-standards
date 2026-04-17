{
  inputs,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) nixSetupStep mkNixInstallStep;
  nixpkgsRev = inputs.nixpkgs.rev;
in
{
  config.definition = {
    name = "Publish to pub.dev";
    on.push.tags = [ "v*" ];
    jobs.publish = {
      runsOn = "ubuntu-latest";
      environment = "pub.dev";
      permissions.id-token = "write";
      steps = [
        { uses = av."actions/checkout"; }
        (nixSetupStep av."cachix/install-nix-action")
        (mkNixInstallStep nixpkgsRev "dart")
        { run = "dart pub get"; }
        { run = "dart pub publish --dry-run"; }
        { run = "dart pub publish -f"; }
      ];
    };
  };
}
