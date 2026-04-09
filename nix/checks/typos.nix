# Typos spell checker.
# Checks source files for common typos.
#
# Usage:
#   checks.famedly-typos = import inputs.engineering-standards + "/nix/checks/typos.nix" { inherit pkgs src; };

{
  pkgs,
  src,
  configFile ? null,
}:
pkgs.runCommand "typos-check" { buildInputs = [ pkgs.typos ]; } ''
  ${if configFile != null then "typos --config ${configFile} ${src}" else "typos ${src}"}
  touch $out
''
