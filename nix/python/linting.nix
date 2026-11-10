## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

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

      # `target-version` is left unset: Ruff reads it from `requires-python`.
      sharedRuff = {
        line-length = 88;
        lint = {
          # Ruff's `I` rules replace isort; `extend-select` keeps Ruff's defaults.
          extend-select = [ "I" ];

          # Turned off across all Python code. From `famedly/synapse-invite-checker`.
          ignore = [
            "FBT001" # Boolean-typed positional argument
            "FBT002" # Boolean default positional argument
            "N802" # Function name should be lowercase
            "N815" # mixedCase variable in class scope
            "PLW0603" # Using the global statement to update a variable
            "TRY002" # Create your own exception
            "TRY003" # Avoid specifying long messages outside the exception class
          ];

          # Patterns a linter reads as smells but which are normal in tests. From
          # `famedly/synapse-invite-checker`.
          per-file-ignores."tests/*" = [
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

      ruffSettings =
        cfg:
        let
          ruff = lib.recursiveUpdate sharedRuff (lib.removeAttrs cfg.ruff [ "disabledRules" ]);
        in
        ruff
        // {
          lint = ruff.lint // {
            ignore = lib.subtractLists cfg.ruff.disabledRules (ruff.lint.ignore or [ ]);
          };
        };

      ruffToml =
        project: cfg:
        managedFile {
          inherit pkgs;

          name = "ruff.toml";
          file = pkgs.writers.writeTOML "ruff.toml" (ruffSettings cfg);

          note = ''
            The shared rules come from the engineering standards. Add
            project-specific rules in `flake.nix` under
            `famedly.standards.python.projects."${project}".ruff`; project
            settings override shared settings.

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
