{
  flakeModules,
  inputs,
  lib,
  ...
}:
importingFlake: {
  config.perSystem =
    { config, pkgs, ... }:
    {
      devshells.standards = {
        name = lib.mkDefault "engineering-standards";

        commands = [
          {
            name = "nix fmt";
            help = "Auto-format all files in the project.";
            category = "[[lints and checks]]";
            package = pkgs.nix;
          }

          {
            name = "prek";
            help = "Run pre-commit hooks on currently staged changes";
            category = "[[lints and checks]]";
            package = config.prek-pre-commit.package.wrapper;
          }

          {
            name = "prek -s main -o HEAD";
            help = "Run pre-commit hooks on all commits in the current branch";
            category = "[[lints and checks]]";
            package = config.prek-pre-commit.package.wrapper;
          }
        ];
      };
    };
}
