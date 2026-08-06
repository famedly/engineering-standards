## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  perSystem.treefmt = {
    programs.nixfmt.enable = true;
    settings.formatter.nixfmt = {
      command = "nixfmt";
      options = [ "--strict" ];
    };
  };
}
