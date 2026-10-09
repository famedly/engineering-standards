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
        # Two distinct treefmt steps, both backed by the same `ruff` binary:
        #   - `ruff-format` runs `ruff format` (the formatter).
        #   - `ruff-check` runs `ruff check --fix` (the autofixable lint rules).
        # The subcommand and flags that set them apart come from treefmt-nix's own
        # `ruff-format` / `ruff-check` program modules; here we only pin which
        # `ruff` they use.
        programs.ruff-format = {
          enable = true;
          package = pkgs.ruff;
        };
        programs.ruff-check = {
          enable = true;
          package = pkgs.ruff;
        };

        # `treefmt.toml` is committed, so it must not embed a store path. Both
        # steps resolve `ruff` from `PATH` instead (the devshell and the `prek`
        # wrapper put it there); the subcommand each one runs is unaffected.
        settings.formatter.ruff-format.command = "ruff";
        settings.formatter.ruff-check.command = "ruff";
      };
    };
}
