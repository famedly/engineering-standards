## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Prepends some header to a file
{
  pkgs,
  header,
  file,
}:
pkgs.runCommand "get-treefmt-toml" { } ''
  cat <<EOF | cat - ${file} > $out
  ${header}
  EOF
''
