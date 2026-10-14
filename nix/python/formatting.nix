## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: {
  config.perSystem =
    { config, pkgs, ... }:
    # `ruff` is only wired into the formatter for repositories that actually
    # contain Python code.
    lib.mkIf (config.famedly.standards.python.projects != { }) {
      treefmt = {
        programs.ruff-format = {
          enable = true;
          package = pkgs.ruff;
        };
        programs.ruff-check = {
          enable = true;
          package = pkgs.ruff;
        };

        # ruff-format runs `ruff format`, ruff-check runs `ruff check --fix`;
        # treefmt-nix supplies those subcommands as `options`.
        settings.formatter.ruff-format.command = "ruff";
        settings.formatter.ruff-check.command = "ruff";
      };
    };
}
