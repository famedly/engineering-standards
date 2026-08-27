## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  standardsLib,
  ...
}:
let
  inherit (config.famedly.standards.ci) steps;
  inherit (standardsLib) inProject;
in
{
  perSystem =
    { config, ... }:
    let
      inherit (config.famedly.standards.dart) projects;
    in
    lib.mkIf (projects != { }) {
      # `dart format` takes the language version from the resolved package
      # config, and formats to the newest version it knows when there is none
      # to read. The style differs between versions, so a job that formats
      # without resolving first disagrees with every editor in the repository
      # and reports the difference as the developer's fault.
      famedly.standards.ci.preCommit.setupSteps =
        lib.optionals (lib.any (project: project.checks.privateDependencies) (
          lib.attrValues projects
        )) steps.privateDependencies
        ++ lib.mapAttrsToList (project: projectConfig: {
          name = "Resolve dependencies${lib.optionalString (project != ".") " in ${project}"}";
          shell = steps.devshell;

          # We pass `--no-example` as in the checks workflow, since a bundled
          # example app needs whatever it needs and no hook looks at it.
          run = inProject project "${projectConfig.cli} pub get --no-example";
        }) projects;
    };
}
