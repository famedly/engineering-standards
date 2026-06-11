{
  flakeModules,
  inputs,
  lib,
  ...
}:
importingFlake: {
  config.perSystem = { config, ... }: {
    devshells.standards.packages = [ config.prek-pre-commit.package.wrapper ];
  };
}
