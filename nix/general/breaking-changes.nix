## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

{ flake-parts-lib, lib, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.breakingChanges = {
      enforce = lib.mkEnableOption ''
        failing the checks that hold a repository to the breaking-changes
        standard, rather than only warning

        Each of them turns something red that passed before: a commit marked
        breaking without migration notes, a release whose version hides a
        break.
      '';

      templates.enable = lib.mkEnableOption ''
        generating a pull request template and an issue form that ask whether
        a change breaks anyone depending on the project

        Opt-in, because the pull request template replaces whatever template
        the repository has
      '';
    };
  });

  config.perSystem =
    { config, ... }:
    let
      cfg = config.famedly.standards.breakingChanges;
    in
    {
      filegen.settings.files = lib.mkIf cfg.templates.enable [
        {
          type = "copy";
          target = ".github/pull_request_template.md";
          source = ../../standards/pull_request_template.md;
        }

        # Beside the template rather than in it, where it would end up in
        # every pull request's description.
        {
          type = "copy";
          target = ".github/pull_request_template.md.license";
          source = ../../standards/pull_request_template.md.license;
        }

        {
          type = "copy";
          target = ".github/ISSUE_TEMPLATE/change.yml";
          source = ../../standards/issue-template-change.yml;
        }
      ];
    };
}
