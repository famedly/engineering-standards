## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: {
  config.perSystem =
    {
      config,
      pkgs,
      standardsLib,
      ...
    }:
    let
      inherit (standardsLib) directory;
      inherit (config.famedly.standards.python) projects;

      # Ruff reads `ruff.toml` in preference to the `[tool.ruff]` table in
      # `pyproject.toml`, so a table left there is dead config: it looks like it
      # configures Ruff but nothing reads it, which is how a setting ends up
      # silently ignored. Nushell parses the TOML and inspects the `tool` table
      # directly, rather than us grepping for a header in a shell script.
      not-in-pyproject = pkgs.writers.writeNuBin "python-ruff-not-in-pyproject" ''
        let pyprojects = ${
          builtins.toJSON (lib.mapAttrsToList (project: _: "${directory project}pyproject.toml") projects)
        }

        mut status = 0

        for pyproject in $pyprojects {
          if not ($pyproject | path exists) { continue }

          if "ruff" in (open $pyproject | get tool? | default {}) {
            print --stderr $"error: ($pyproject) still configures Ruff under [tool.ruff]."
            print --stderr "       Ruff reads ruff.toml in preference, so that table has no effect."
            print --stderr "       Move anything it holds into the project's ruff config in flake.nix and delete it."
            $status = 1
          }
        }

        exit $status
      '';

      # The standards format Python with `ruff format`. Black can be in
      # three places: a `[tool.black]` table, a hatch env's dependency list, or a
      # hatch script that runs it. Parse the TOML and inspect all three.
      no-black = pkgs.writers.writeNuBin "python-no-black" ''
        # PEP 508 package name: the leading token before any version, extras, or
        # marker. Enough to tell `black==24.1` and `black[d]` from `blacken-docs`.
        def pkg-name [dep: string] {
          $dep | str downcase | str trim | split row -r '[\s\[=<>!~@;(]' | first
        }

        def cmd-uses-black [cmd] {
          let cmds = if ($cmd | describe) =~ '^list' { $cmd } else { [$cmd] }
          $cmds | any {|c| ($c | split row -r '\s+') | any {|t| $t == "black" } }
        }

        let pyprojects = ${
          builtins.toJSON (lib.mapAttrsToList (project: _: "${directory project}pyproject.toml") projects)
        }

        mut status = 0

        for pyproject in $pyprojects {
          if not ($pyproject | path exists) { continue }

          let tool = (open $pyproject | get tool? | default {})
          mut uses_black = ("black" in $tool)

          for hatch_env in ($tool | get hatch?.envs? | default {} | transpose name cfg) {
            let deps = ($hatch_env.cfg | get dependencies? | default []) | append ($hatch_env.cfg | get extra-dependencies? | default [])
            if ($deps | any {|d| (pkg-name $d) == "black" }) { $uses_black = true }

            for script in ($hatch_env.cfg | get scripts? | default {} | transpose name cmd) {
              if (cmd-uses-black $script.cmd) { $uses_black = true }
            }
          }

          if $uses_black {
            print --stderr $"error: ($pyproject) still configures black."
            print --stderr "       The standards format Python with ruff format, which replaces black."
            print --stderr "       Remove its [tool.black] table, hatch env dependencies, and format scripts."
            $status = 1
          }
        }

        exit $status
      '';
    in
    lib.mkIf (projects != { }) {
      prek-pre-commit = {
        package.runtimePkgs = [
          not-in-pyproject
          no-black
        ];

        workspaces.".".repos = [
          {
            repo = "local";

            hooks = [
              {
                id = not-in-pyproject.meta.mainProgram;
                name = not-in-pyproject.meta.mainProgram;
                description = "Reject a [tool.ruff] table in pyproject.toml, which Ruff ignores when ruff.toml exists";

                entry = not-in-pyproject.meta.mainProgram;
                # Checks a file that may be absent, so it runs regardless of what
                # is staged rather than being handed a file list.
                pass_filenames = false;

                language = "system";
              }
              {
                id = no-black.meta.mainProgram;
                name = no-black.meta.mainProgram;
                description = "Reject black config in pyproject.toml, since ruff format replaces it";

                entry = no-black.meta.mainProgram;
                # Checks a file that may be absent, so it runs regardless of what
                # is staged rather than being handed a file list.
                pass_filenames = false;

                language = "system";
              }
            ];
          }
        ];
      };
    };
}
