## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: {
  config.perSystem =
    { config, pkgs, ... }:
    # The Python toolchain is only pulled in for repositories that actually
    # contain Python code.
    lib.mkIf (config.famedly.standards.python.projects != { }) {
      devshells.python = {
        packages = [
          config.famedly.standards.python.interpreter

          # The project manager we standardise on, and the installer it drives.
          # `hatch` and `uv` come pinned through the standards' nixpkgs, so every
          # developer resolves with the same versions.
          pkgs.hatch
          pkgs.uv

          # Formatter and linter. Also reaches the shell through the `treefmt`
          # programs, but a project may want to run it directly. Taken from the
          # toolchain so it matches what the formatter and the hooks use.
          config.famedly.standards.python.ruff
        ];

        # TODO: Find a better way to inherit devshell configurations.
        commands = lib.filter (command: command.name != "menu") config.devshells.standards.commands;
      };
    };
}
