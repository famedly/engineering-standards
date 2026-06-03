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
    (importApply ./git-cliff.nix args)
    (importApply ./pre-commit-hooks.nix args)
  ];

  # Install all defined GitHub workflows
  config.perSystem =
    { config, ... }:
    {
      githubActions.enable = true;

      filegen.settings.files = lib.mkIf (config.githubActions.workflows != { }) (
        lib.mapAttrsToList (workflow: source: {
          type = "copy";
          target = "./.github/workflows/${workflow}";
          inherit source;
          clobber = true;
        }) config.githubActions.workflowFiles
      );
    };
}
