# REUSE license compliance check.
# Verifies that all files have proper license headers per the REUSE spec.
# See https://reuse.software

{ pkgs, src }:
pkgs.runCommand "reuse-check"
  {
    buildInputs = [ pkgs.reuse ];
    inherit src;
  }
  ''
    cd ${src}
    reuse lint
    touch $out
  ''
