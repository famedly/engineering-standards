{
  flakeModules,
  inputs,
  lib,
  ...
}:
importingFlake: {
  config.perSystem =
    { pkgs, ... }:
    {
      devshells.standards.packages = [ pkgs.prek ];
    };
}
