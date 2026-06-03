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
    ./ff-merge_workflow.nix
  ];

  # Install all defined GitHub workflows
  config.perSystem =
    { config, ... }:
    {
      githubActions.enable = true;

      filegen.settings.files = (
        [
          {
            type = "copy";
            target = "./.editorconfig";
            source = ../../standards/editorconfig.toml;
            clobber = true;
          }
        ]
        ++ lib.optionals (config.githubActions.workflows != { }) (
          lib.mapAttrsToList (workflow: source: {
            type = "copy";
            target = "./.github/workflows/${workflow}";
            inherit source;
            clobber = true;
          }) config.githubActions.workflowFiles
        )
      );
    };
}
