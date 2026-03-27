{
  config,
  lib,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib) ghEnv;
in
{
  options.envFile = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Path to .env file for version overrides.";
  };

  config.definition = {
    name = "Publish to pub.dev";
    on.push.tags = [ "v*" ];
    jobs.publish = {
      runsOn = "ubuntu-latest";
      environment = "pub.dev";
      permissions.id-token = "write";
      steps = [
        { uses = "actions/checkout@${av.checkout}"; }
      ]
      ++ lib.optionals (config.envFile != "") [
        {
          name = "Read env file";
          run = "cat ${config.envFile} >> $GITHUB_ENV";
        }
      ]
      ++ [
        {
          uses = "dart-lang/setup-dart@${av.setupDart}";
          with_.sdk = ghEnv "dart_version || 'stable'";
        }
        { run = "dart pub get"; }
        { run = "dart pub publish --dry-run"; }
        { run = "dart pub publish -f"; }
      ];
    };
  };
}
