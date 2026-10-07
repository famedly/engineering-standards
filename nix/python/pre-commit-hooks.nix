## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: {
  perSystem =
    {
      config,
      pkgs,
      standardsLib,
      ...
    }:
    let
      inherit (standardsLib) directory;

      inherit (config.famedly.standards.python) projects;

      # Forgetting the `extend` is silent: `ruff` just falls back to its own
      # defaults plus whatever the project's `ruff.toml` says, without the shared
      # rule set and without telling anyone.
      extends-standards = pkgs.writeShellApplication {
        name = "python-ruff-extends-standards";
        runtimeInputs = [ pkgs.gnugrep ];

        text = ''
          status=0

          check() {
            managed="$1"
            own="$2"

            if [ ! -f "$own" ]; then
              printf 'error: %s does not exist.\n' "$own"
            elif ! grep -qE "^extend[[:space:]]*=[[:space:]]*[\"']?(\./)?$managed" "$own"; then
              printf 'error: %s does not extend the managed Ruff config.\n' "$own"
            else
              return 0
            fi

            printf '       Without it the standard rule set has no effect. Add:\n\n         extend = "%s"\n\n' "$managed"
            status=1
          }

          ${lib.concatLines (
            lib.mapAttrsToList (
              project: _: ''check ruff.standards.toml "${directory project}ruff.toml"''
            ) projects
          )}
          exit "$status"
        '';
      };

      # Ruff reads `ruff.toml` in preference to the `[tool.ruff]` table in
      # `pyproject.toml`, so a table left there is dead config: it looks like it
      # configures Ruff but nothing reads it, which is how a setting ends up
      # silently ignored.
      not-in-pyproject = pkgs.writeShellApplication {
        name = "python-ruff-not-in-pyproject";
        runtimeInputs = [ pkgs.gnugrep ];

        text = ''
          status=0

          check() {
            pyproject="$1"

            if [ -f "$pyproject" ] && grep -qE '^\[tool\.ruff' "$pyproject"; then
              printf 'error: %s still configures Ruff under [tool.ruff].\n' "$pyproject"
              printf '       Ruff reads ruff.toml in preference, so that table has no effect.\n'
              printf '       Move anything it holds into ruff.toml and delete it.\n\n'
              status=1
            fi
          }

          ${lib.concatLines (
            lib.mapAttrsToList (project: _: ''check "${directory project}pyproject.toml"'') projects
          )}
          exit "$status"
        '';
      };

      hook = drv: description: {
        id = drv.meta.mainProgram;
        name = drv.meta.mainProgram;
        inherit description;

        entry = drv.meta.mainProgram;
        # This checks for files that may be absent.
        pass_filenames = false;

        language = "system";
      };
    in
    lib.mkIf (projects != { }) {
      prek-pre-commit = {
        package.runtimePkgs = [
          extends-standards
          not-in-pyproject
        ];

        workspaces.".".repos = [
          {
            repo = "local";

            hooks = [
              (hook extends-standards "Ensure each project's ruff.toml extends the managed ruff.standards.toml")

              (hook not-in-pyproject "Reject a [tool.ruff] table in pyproject.toml, which Ruff ignores when ruff.toml exists")
            ];
          }
        ];
      };
    };
}
