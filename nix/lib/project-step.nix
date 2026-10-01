## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# A step that runs one command inside one project's directory, with the
# toolchain from the repository's devshell — the shape of most steps a
# language workflow has.
{
  shell,
  project,
  inProject,
}:
name: run: {
  inherit name shell;
  run = inProject project run;
}
