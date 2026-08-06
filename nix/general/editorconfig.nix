## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  perSystem = {
    filegen.settings.files = [
      {
        type = "copy";
        target = ".editorconfig";
        source = ../../standards/editorconfig;
      }
    ];
  };
}
