## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Helpers for the keys of the `famedly.standards.*.projects` options, which are
# paths relative to the repository root: `.` for a repository that is one
# project, `./packages/foo` for one that holds several.
{ lib }: {
  # Prefix for file names inside the project, empty at the repository root.
  directory = project: if project == "." then "" else "${lib.removePrefix "./" project}/";

  # Workflow and job ids may contain neither `/` nor `.`, so derive a suffix
  # from the project path. Empty at the repository root, which keeps the names
  # of single-project repositories plain.
  suffix =
    project:
    if project == "." then
      ""
    else
      "-${
        lib.replaceStrings
          [
            "./"
            "/"
            "."
          ]
          [
            ""
            "-"
            "-"
          ]
          project
      }";
}
