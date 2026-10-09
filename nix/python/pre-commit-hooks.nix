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
    in
    lib.mkIf (projects != { }) {
      prek-pre-commit = {
        package.runtimePkgs = [ not-in-pyproject ];

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
            ];
          }
        ];
      };
    };
}
