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
  ];

  config.perSystem =
    { config, ... }:
    lib.mkMerge [
      {
        filegen.settings.clobber-by-default = true;
        githubActions.enable = true;
      }

      (lib.mkIf (config.githubActions.workflows != { }) {
        filegen.settings.files = lib.mapAttrsToList (workflow: source: {
          type = "copy";
          target = "./.github/workflows/${workflow}";
          inherit source;
        }) config.githubActions.workflowFiles;
      })
    ];
}
