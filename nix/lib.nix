# Shared Nix utilities for engineering-standards modules.
{ lib }:
{
  # Build a list of (src, dest) pairs from all files in a directory.
  filesFromDir =
    dir: destPrefix:
    if builtins.pathExists dir then
      lib.mapAttrsToList (name: _: {
        src = "${dir}/${name}";
        dest = if destPrefix == "" then name else "${destPrefix}/${name}";
      }) (builtins.readDir dir)
    else
      [ ];
}
