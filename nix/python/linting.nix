## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Generates the shared `ruff.standards.toml` for each Python project.
#
# We own this file rather than writing into the project's `ruff.toml`, which
# holds the project's own overrides and which `filegen` would clobber. Each
# project keeps a `ruff.toml` that extends this one; the
# `python-ruff-extends-standards` hook checks that it does.
{ lib, ... }:
let
  # Rules we turn off across all Python code, on top of Ruff's default
  # selection. Taken from `famedly/synapse-invite-checker`.
  ignore = [
    "FBT001" # Boolean-typed positional argument
    "FBT002" # Boolean default positional argument
    "N802" # Function name should be lowercase
    "N815" # mixedCase variable in class scope
    "PLW0603" # Using the global statement to update a variable
    "TRY002" # Create your own exception
    "TRY003" # Avoid specifying long messages outside the exception class
  ];

  # Rules that don't apply to test code, which leans on patterns a linter reads
  # as smells but which are normal in tests. Taken from
  # `famedly/synapse-invite-checker`.
  testIgnore = [
    "N803" # Argument name should be lowercase
    "PLR2004" # Magic value used in comparison
    "PT019" # Fixture without value injected as parameter
    "S101" # Use of assert detected
    "S105" # Possible hardcoded password
    "SLF001" # Private member accessed
    "UP035" # Deprecated import
    "UP046" # Generic class uses type parameters (PEP 695)
    "UP047" # Generic function uses type parameters (PEP 695)
  ];
in
{
  config.perSystem =
    {
      config,
      pkgs,
      standardsLib,
      ...
    }:
    let
      inherit (standardsLib) directory;
      inherit (config.famedly.standards.python) projects pythonVersion;

      # `3.10` → `py310`, the form Ruff names a target version with.
      target = "py" + lib.replaceStrings [ "." ] [ "" ] pythonVersion;

      # A standalone Ruff config, so the keys sit at the top level rather than
      # under a `[tool.ruff]` table the way they would in `pyproject.toml`.
      standards = {
        target-version = target;
        line-length = 88;

        lint = {
          # Import sorting. Ruff's `I` rules replace isort, so the import layout
          # black and isort produced survives the switch to `ruff format`.
          extend-select = [ "I" ];

          inherit ignore;

          per-file-ignores = {
            "tests/*" = testIgnore;
          };
        };
      };

      standardsFile = standardsLib.managedFile {
        inherit pkgs;

        name = "ruff.standards.toml";
        file = pkgs.writers.writeTOML "ruff.standards.toml" standards;

        note = ''
          This holds the shared Ruff rules. Keep each project's own `ruff.toml`
          next to it with:

            extend = "ruff.standards.toml"

          Put repository-specific rules there, for example extra `tests/*`
          ignores through `extend-per-file-ignores`. The
          `python-ruff-extends-standards` hook checks that the `extend` is
          present; without it this rule set has no effect.

          Remove any `[tool.ruff]` table from `pyproject.toml`, since Ruff reads
          `ruff.toml` in preference to it.
        '';
      };

      # We only write the managed file. The project's own `ruff.toml` has to
      # extend it, which the `python-ruff-extends-standards` hook checks. Writing
      # that one ourselves would trample the overrides it is meant to hold, since
      # `filegen` has no create-once mode.
      mkProjectFiles = project: _: [
        {
          type = "copy";
          target = "./${directory project}ruff.standards.toml";
          source = standardsFile;
          clobber = true;
        }
      ];
    in
    {
      filegen.settings.files = lib.concatLists (lib.mapAttrsToList mkProjectFiles projects);
    };
}
