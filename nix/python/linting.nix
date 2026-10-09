## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Generates each Python project's `ruff.toml` from the shared standards plus the
# project's own overrides (`famedly.standards.python.projects.<path>.ruff`).
#
# The standards own this file and overwrite it on each `filegen-activate`, so
# project-specific rules live in `flake.nix` rather than in a hand-maintained
# `ruff.toml`.
{ lib, ... }: {
  config.perSystem =
    {
      config,
      pkgs,
      standardsLib,
      ...
    }:
    let
      inherit (standardsLib) directory managedFile;
      inherit (config.famedly.standards.python) projects;

      # The shared Ruff rules, laid out as a standalone `ruff.toml` (keys at the
      # top level rather than under a `[tool.ruff]` table). `target-version` is
      # left unset on purpose: Ruff reads it from `requires-python` in
      # `pyproject.toml`, so the supported version is declared in one place.
      standards = {
        line-length = 88;

        lint = {
          # Import sorting. Ruff's `I` rules replace isort, so the import layout
          # black and isort produced survives the switch to `ruff format`.
          extend-select = [ "I" ];

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

          # Rules that don't apply to test code, which leans on patterns a linter
          # reads as smells but which are normal in tests. Taken from
          # `famedly/synapse-invite-checker`.
          per-file-ignores = {
            "tests/*" = [
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
          };
        };
      };

      # The project's own `ruff` overrides win over the shared defaults. Downstream
      # should reach for Ruff's `extend-*` keys to add to the shared lists rather
      # than replacing them wholesale.
      ruffToml =
        project: cfg:
        managedFile {
          inherit pkgs;

          name = "ruff.toml";
          file = pkgs.writers.writeTOML "ruff.toml" (lib.recursiveUpdate standards cfg.ruff);

          note = ''
            The shared rules come from the engineering standards. Add
            project-specific rules in `flake.nix` under
            `famedly.standards.python.projects."${project}".ruff`, using Ruff's
            `extend-*` keys to extend the shared lists.

            Declare the supported Python version with `requires-python` in
            `pyproject.toml`; Ruff reads its target version from there.
          '';
        };

      mkProjectFile = project: cfg: {
        type = "copy";
        target = "./${directory project}ruff.toml";
        source = ruffToml project cfg;
        clobber = true;
      };
    in
    {
      filegen.settings.files = lib.mapAttrsToList mkProjectFile projects;
    };
}
