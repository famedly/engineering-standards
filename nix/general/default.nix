## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
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
    ./editorconfig.nix
    ./formatting.nix
    (importApply ./pre-commit-hooks.nix args)
    ./reuse.nix

    ./workflows/ci-steps.nix
    ./workflows/check-commit-messages.nix
    ./workflows/check-pre-commit-hooks.nix
    ./workflows/release.nix
  ];

  options.famedly.standards = {
    isOpenSource = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the project should be considered "open source". If it is
        open source, the resulting image will be published to our public OCI
        registry.

        **Caution:** If set, the resulting binaries will become publicly
        accessible.
      '';
    };
  };

  perSystem =
    { config, ... }:
    lib.mkMerge [
      { githubActions.enable = true; }

      (lib.mkIf (config.githubActions.workflows != { }) {
        filegen.settings.files = lib.mapAttrsToList (workflow: source: {
          type = "copy";
          target = "./.github/workflows/${workflow}";
          inherit source;
        }) config.githubActions.workflowFiles;
      })
    ];
}
