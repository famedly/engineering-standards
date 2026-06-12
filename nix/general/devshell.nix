{
  flakeModules,
  inputs,
  lib,
  ...
}:
importingFlake: {
  config.perSystem =
    { config, ... }:
    {
      devshells.standards = {
        name = lib.mkDefault "engineering-standards";

        commands = [
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
