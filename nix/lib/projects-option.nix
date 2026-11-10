## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The `projects` option every language module set declares: one relative path
# per project, plus whatever one project of that language can be configured
# with.
{ lib }:
{
  language,
  kind ? language,
  example,
  submodule ? { },
}:
lib.mkOption {
  description = ''
    ${language} projects in the repository that should be equipped with
    our standards.

    This must be a relative path starting with `.`. Simply use `.` if the
    whole project is a ${kind} project.
  '';

  default = { };
  inherit example;

  type = lib.types.attrsOf (lib.types.submodule submodule);
}
