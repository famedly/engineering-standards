## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Prepends some header to a file
{
  pkgs,
  header,
  file,
}:
let
  headerFile = pkgs.writeText "headerFile" header;
in
pkgs.runCommand "get-treefmt-toml" { } "cat ${headerFile} ${file} > $out"
