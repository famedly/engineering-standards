## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ flake-parts-lib, lib, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { pkgs, ... }: {
      options.famedly.standards.editorconfig = {
        enable = lib.mkOption {
          default = true;
          example = true;
          description = "Whether to generate an editorconfig file";
          type = lib.types.bool;
        };
      };
    }
  );

  config.perSystem = { config, lib, ... }: {
    filegen.settings.files = lib.mkIf config.famedly.standards.editorconfig.enable [
      {
        type = "copy";
        target = ".editorconfig";
        source = ../../standards/editorconfig;
      }
    ];
  };
}
