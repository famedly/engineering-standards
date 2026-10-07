## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: {
  config.perSystem =
    { config, ... }:
    # `ruff` is only wired into the formatter for repositories that actually
    # contain Python code.
    lib.mkIf (config.famedly.standards.python.projects != { }) {
      treefmt = {
        # We standardise on `ruff format`. It reads the
        # project's `ruff.toml`, which extends the generated
        # `ruff.standards.toml`, so line length and target version come from
        # there rather than being restated here.
        programs.ruff-format = {
          enable = true;
          package = config.famedly.standards.python.ruff;
        };

        # `ruff check --fix` applies the autofixable lint rules. The rule set
        # lives in the generated `ruff.standards.toml`.
        programs.ruff-check = {
          enable = true;
          package = config.famedly.standards.python.ruff;
        };

        # `treefmt.toml` is committed, so it must not contain store paths. `ruff`
        # is on `PATH` via the devshell and the `prek` wrapper.
        settings.formatter.ruff-format.command = "ruff";
        settings.formatter.ruff-check.command = "ruff";
      };
    };
}
