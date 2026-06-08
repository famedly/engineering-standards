{ flake-parts-lib, lib, ... }:
let
  inherit (lib) types;
  smfh.version = 3;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { pkgs, ... }:
    {
      options.filegen = {
        settings = {
          files = lib.mkOption {
            description = "";
            default = [ ];

            type = types.listOf (
              types.submodule {
                options = {
                  type = lib.mkOption {
                    description = "";

                    type = types.enum [
                      "copy"
                      "symlink"
                      "modify"
                      "directory"
                      "delete"
                    ];
                  };

                  target = lib.mkOption {
                    description = "";
                    type = types.pathWith { absolute = false; };
                  };

                  source = lib.mkOption {
                    description = "";
                    type = types.nullOr types.path;
                  };

                  clobber = lib.mkOption {
                    description = "";
                    type = types.nullOr types.bool;
                  };

                  ignore-modification = lib.mkOption {
                    description = "";
                    type = types.nullOr types.bool;
                  };

                  deactivate = lib.mkOption {
                    description = "";
                    type = types.nullOr types.bool;
                  };

                  # Not implemented:
                  #
                  # - permissions/uid/gid, as these should not matter for a
                  #   project repo.
                  # - follow_symlinks, since for a git repo we should never
                  #   want to symlink to absolute paths.
                };
              }
            );
          };

          clobber-by-default = lib.mkOption {
            description = "";
            type = types.nullOr types.bool;
          };
        };

        smfhPackage = lib.mkOption {
          description = ''
            The smfh package to use.
          '';
          default = pkgs.smfh;
          defaultText = "pkgs.smfh";
          type = types.package;
        };

        scripts = {
          activate = lib.mkOption {
            description = ''
              A script that applies the files configured with `filegen.files`.
            '';
            readOnly = true;
            type = types.pathInStore;
          };

          deactivate = lib.mkOption {
            description = ''
              A script that removes configured by a previous invocation of the activate script.
            '';
            readOnly = true;
            type = types.pathInStore;
          };
        };
      };
    }
  );

  config.perSystem =
    { pkgs, config, ... }:
    let
      cfg = config.filegen;
      new-manifest = pkgs.writers.writeJSON "filegen-manifest.json" (
        config.filegen.settings // { inherit (smfh) version; }
      );
    in
    {
      apps =
        let
          activate = pkgs.writers.writeNu "filegen-apply-script" ''
            cd (git rev-parse --show-toplevel)

            mkdir .config

            if ('.config/filegen-manifest.json' | path exists) {
              ${lib.getExe cfg.smfhPackage} --impure diff .config/filegen-manifest.json ${new-manifest}
            } else {
              ${lib.getExe cfg.smfhPackage} --impure activate ${new-manifest} 
            }

            cp --preserve [] ${new-manifest} .config/filegen-manifest.json
          '';

          deactivate = pkgs.writers.writeNu "filegen-deactivate-script" ''
            cd (git rev-parse --show-toplevel)
            ${lib.getExe cfg.smfhPackage} deactivate .config/filegen-manifest.json
          '';
        in
        {
          filegen-activate = {
            program = activate.outPath;
            meta.description = "Install files defined by the `filegen` options of this flake";
          };

          filegen-deactivate = {
            program = deactivate.outPath;
            meta.description = "Uninstall all files previously installed using `filegen-activate`";
          };
        };
    };
}
