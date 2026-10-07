## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: {
  config.perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.famedly.standards.python) interpreter ruff;

      # The standards shell's menu, minus its welcome line, so the Python shell
      # keeps `nix fmt` and the `prek` entries rather than restating them.
      # TODO: Find a better way to inherit devshell configurations.
      standardsCommands = lib.filter (
        command: command.name != "menu"
      ) config.devshells.standards.commands;
    in
    # The Python toolchain is only pulled in for repositories that actually
    # contain Python code. It lives in a shell of its own, like `rust`; a project
    # aliases it to its `default` so `nix develop` lands here.
    lib.mkIf (config.famedly.standards.python.projects != { }) {
      devshells.python = { config, ... }: {
        name = lib.mkDefault "python";

        packages = [
          interpreter

          # The project manager we standardise on, and the installer it drives.
          # `hatch` and `uv` come pinned through the standards' nixpkgs, so every
          # developer resolves with the same versions.
          pkgs.hatch
          pkgs.uv

          # Formatter and linter. Also reaches the shell through the `treefmt`
          # programs, but a project may want to run it directly. Taken from the
          # toolchain so it matches what the formatter and the hooks use.
          ruff
        ];

        commands = standardsCommands ++ [
          # `hatch shell` is a convenience, not a startup hook.
          {
            name = "hatch shell";
            help = "Enter the project's hatch environment";
            category = "[[python]]";
            package = pkgs.hatch;
          }
        ];

        # Print the pinned toolchain versions on entry, so it is obvious which
        # builds the standards resolved. The `$(...)` run only on an interactive
        # or direnv entry, never under `nix develop -c`, so they don't disturb a
        # scripted `nix develop -c hatch --version`.
        motd = ''
          {202}🔨 Welcome to ${config.name}{reset}

          {bold}[[toolchain]]{reset}
            $(python3 --version)
            $(hatch --version)
            $(uv --version)
            $(ruff --version)

          $(type -p menu &>/dev/null && menu)
        '';
      };
    };
}
