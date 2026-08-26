## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Prepends the header every file we generate carries: the licence, that the file
# is ours rather than the repository's, and how to regenerate it.
#
# The text used to be written out at each of the six places that place such a
# file, so a repository could be told two different things about the same kind
# of file depending on which module wrote it.
#
# `note` is anything else the reader of that particular file needs — where the
# real knob lives, what the project has to depend on — as plain prose, without
# the comment markers.
{ lib }:
{
  pkgs,
  name,
  file,
  note ? null,
}:
let
  comment =
    text:
    lib.concatLines (
      map (line: if line == "" then "#" else "# ${line}") (
        lib.splitString "\n" (lib.removeSuffix "\n" text)
      )
    );

  header = pkgs.writeText "${name}.header" (
    ''
      ## SPDX-FileCopyrightText: 2026 Famedly GmbH
      ##
      ## SPDX-License-Identifier: Apache-2.0

      # managed-by: engineering-standards — do not edit manually.
      #
      # Regenerate with `nix run .#filegen-activate`.
    ''
    + lib.optionalString (note != null) ("#\n" + comment note)
    + "\n"
  );
in
pkgs.runCommand name { } "cat ${header} ${file} >$out"
