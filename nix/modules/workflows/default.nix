{
  inputs,
  lib,
  flake-parts-lib,
  ...
}:
_caller-args:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    ;
  inherit (flake-parts-lib) mkPerSystemOption;
in
{
  imports = [ inputs.github-actions-nix.flakeModules.default ];

  options.perSystem = mkPerSystemOption (
    { config, options, ... }:
    {
      options.famedly.github = {
        settings.ociRegistryURLs = {
          snapshots = mkOption {
            type = types.str;
            default = "registry.famedly.net/docker-nightly";
            visible = false;
            description = "OCI registry for unreleased snapshots.";
          };
          releases = mkOption {
            type = types.str;
            default = "registry.famedly.net/docker-releases";
            visible = false;
            description = "OCI registry for proprietary releases.";
          };
          openSourceReleases = mkOption {
            type = types.str;
            default = "registry.famedly.net/docker-oss";
            visible = false;
            description = "OCI registry for open-source releases.";
          };
        };

        workflows =
          let
            repoRoot = ../../..;
            workflowsLib = import ./lib.nix { inherit lib; };

            mkWorkflow = name: {
              inherit name;
              value = mkOption {
                default = { };
                type = types.submoduleWith {
                  specialArgs = {
                    inherit inputs repoRoot;
                    inherit workflowsLib;
                    famedlyConfig = config.famedly;
                  };

                  modules = [
                    {
                      options = {
                        enable = mkEnableOption "the Famedly ${name} workflow";

                        definition = mkOption {
                          type = options.githubActions.workflows.type.nestedTypes.elemType;
                        };

                        extraManagedFiles = mkOption {
                          type = types.listOf (
                            types.submodule {
                              options = {
                                src = mkOption { type = types.path; };
                                dest = mkOption { type = types.str; };
                                initialOnly = mkOption {
                                  type = types.bool;
                                  default = false;
                                };
                              };
                            }
                          );
                          default = [ ];
                          description = "Additional managed files (composite actions, scripts).";
                        };
                      };
                    }
                    (./definitions + "/${name}.nix")
                  ];
                };
              };
            };
          in
          lib.pipe (builtins.readDir ./definitions) [
            (lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".nix" file))
            (lib.mapAttrs' (file: _: mkWorkflow (lib.removeSuffix ".nix" file)))
          ];
      };
    }
  );

  config.perSystem =
    { config, ... }:
    lib.mkIf (lib.any (workflow: workflow.enable) (lib.attrValues config.famedly.github.workflows)) {
      githubActions = {
        enable = true;
        workflows = lib.pipe config.famedly.github.workflows [
          (lib.filterAttrs (_: workflow: workflow.enable))
          (lib.mapAttrs (_: workflow: workflow.definition))
        ];
      };

      famedly.standards._internal.managedFiles = lib.pipe config.famedly.github.workflows [
        (lib.filterAttrs (_: workflow: workflow.enable))
        (lib.mapAttrsToList (
          name: workflow:
          [
            {
              src = config.githubActions.workflowFiles."${name}.yml";
              dest = ".github/workflows/${name}.yml";
            }
          ]
          ++ workflow.extraManagedFiles
        ))
        lib.flatten
      ];
    };
}
