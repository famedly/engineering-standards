{
  flake-parts-lib,
  lib,
  importApply,
  ...
}@args:
importingFlake: {
  imports = [
    ./action-versions.nix
    (importApply ./devshell.nix args)
    (importApply ./pre-commit-hooks.nix args)

    ./workflows/check-pre-commit-hooks.nix
  ];

  config.perSystem =
    { config, ... }:
    lib.mkMerge [
      {
        githubActions.enable = true;
      }

      (lib.mkIf (config.githubActions.workflows != { }) {
        filegen.settings.files = lib.mapAttrsToList (workflow: source: {
          target = "./.github/workflows/${workflow}";
          inherit source;
        }) config.githubActions.workflowFiles;
      })
    ];
}
