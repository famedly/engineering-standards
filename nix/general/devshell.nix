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

        # Include all packages from pre-commit in the shell
        # - This allows easy access to the individual checks, if developers are interested in running them
        # - `prek install` doesn't install the wrapped binary, so when executing the hooks, all runtimePkgs
        #   would be missing if they were not in the shell
        packages = builtins.map (package: package.data) config.prek-pre-commit.package.runtimePkgs;

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
