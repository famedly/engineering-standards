{ filegen, wrappers, ... }:
{ flake-parts-lib, lib, ... }:
let
  inherit (lib) types;
in
{
  imports = [ filegen ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { pkgs, ... }:
    let
      settingsFormat = pkgs.formats.yaml { };
    in
    {
      options.prek-pre-commit = {
        package = lib.mkOption {
          description = "The `prek` package to use to execute pre-commit hooks";
          type = wrappers.lib.types.subWrapperModule {
            imports = [ wrappers.lib.modules.default ];

            pkgs = lib.mkDefault pkgs;
            package = lib.mkDefault pkgs.prek;
          };
        };

        workspaces = lib.mkOption {
          description = ''
            `prek` configuration for each workspace.

            Any hooks defined *must* run either under the `pre-commit` or `pre-push`
            stage to be picked up by CI.

            `pre-push` hooks are intended to be used for heavier work that we don't
            want to run on every commit (so that rebases stay spiffy).

            Note that any hooks that depend on system packages being installed
            should have their packages installed via the
            `prek-pre-commit.package.runtimePkgs` option.

            See the [`prek` documentation](https://prek.j178.dev/workspace/) for details.
          '';
          default = { };
          type = types.attrsOf (
            types.submodule {
              freeformType = settingsFormat.type;

              options.repos = lib.mkOption {
                description = ''
                  The prek `repos` to configure.

                  See https://prek.j178.dev/reference/configuration/#repos-required
                '';

                type = lib.types.listOf (
                  lib.types.submodule {
                    freeformType = settingsFormat.type;

                    options.hooks = lib.mkOption {
                      description = ''
                        The prek `hooks` to configure for this repo.

                        See https://prek.j178.dev/reference/configuration/#hook-entries
                      '';
                      default = [ ];

                      type = lib.types.listOf (
                        lib.types.submodule {
                          freeformType = settingsFormat.type;

                          options.stages = lib.mkOption {
                            description = ''
                              The stages during which to run this pre-commit.

                              Only `pre-push` is currently supported.
                            '';
                            default = [ ];
                            apply =
                              stages:
                              if stages != [ ] && stages != [ "pre-push" ] then
                                builtins.abort ''
                                  Invalid hook stages.

                                  Currently, only pre-push hooks are allowed. To make CI scripting easier,
                                  we're forcing all other hooks to be defined as running under all stages.

                                  If you want to use a different stage, or want to explicitly run a specific
                                  hook only during pre-commit, talk to the engineering-standards maintainers.

                                ''
                              else
                                stages;
                          };
                        }
                      );
                    };
                  }
                );
                default = [ ];
              };
            }
          );
        };
      };
    }
  );

  config.perSystem =
    { config, pkgs, ... }:
    let
      settingsFormat = pkgs.formats.yaml { };
    in
    {
      filegen.settings.files = lib.mapAttrsToList (workspace: config: {
        type = "copy";

        target = "${workspace}/.pre-commit-config.yaml";
        source = settingsFormat.generate "pre-commit-config.yaml" config;
      }) config.prek-pre-commit.workspaces;
    };
}
