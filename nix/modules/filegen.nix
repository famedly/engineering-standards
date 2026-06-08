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
            description = ''
              Declare file manipulations to perform in the project directory.

              This is intended to do things like create GitHub workflow files,
              pre-commit hook configuration, or to generate or place other
              miscellaneous configuration files used for development in the
              repository.

              To generate the files, an "app" named `filegen-activate` is created,
              which can be executed with `nix run .#filegen-activate`.

              The configuration is as expected by
              [smfh](https://github.com/feel-co/smfh), which is used
              to perform the actual file manipulations.

              ---

              Note: This module does *not* attempt to protect against writes to or
              reads from files outside of the repository.

              Trying to protect against this is considered somewhat pointless; At
              the end of the day, you have to trust (or inspect) the flakes whose
              code you execute anyway, as they can simply override what this module
              does. A future version might however still add checks simply to
              prevent mistakes and anti-patterns.
            '';
            default = [ ];

            type = types.listOf (
              types.submodule (
                { config, ... }:
                {
                  options = {
                    type = lib.mkOption {
                      description = ''
                        The type of operation to perform on the given file.

                        Normally, this should be set to `copy`.
                      '';

                      type = types.enum [
                        "copy"
                        "symlink"
                        "modify"
                        "directory"
                        "delete"
                      ];
                    };

                    target = lib.mkOption {
                      description = ''
                        The target of the file operation.

                        To create a file in-repo, use `.` as the project root.
                      '';
                      type = types.pathWith { absolute = false; };
                    };

                    source = lib.mkOption {
                      description = ''
                        The source of the file operation.

                        This *can* be a nix store path, potentially created by interpolating a
                        variable.
                      '';
                      type = types.nullOr types.path;
                    };

                    clobber = lib.mkOption {
                      description = ''
                        Whether to overwrite files that already exist.
                      '';
                      type = types.nullOr types.bool;
                    };

                    ignore-modification = lib.mkOption {
                      description = ''
                        Whether to skip content integrity checks during activation.
                      '';
                      type = types.nullOr types.bool;
                    };

                    deactivate = lib.mkOption {
                      description = ''
                        If enabled, `filegen-deactivate` will ignore this file.
                      '';
                      type = types.nullOr types.bool;
                    };

                    permissions = lib.mkOption {
                      description = ''
                        The permissions of the created file.

                        Only the execute bit will be preserved by git, so this should
                        practically always be "600" or "700", but other values are
                        technically possible.
                      '';
                      type = types.str;

                      # Since creating read-only files can cause
                      # issues, and nix store paths are by default
                      # read-only, we cautiously set this to 600 by
                      # default.
                      default = "600";
                    };

                    # Not implemented:
                    #
                    # - permissions/uid/gid, as these should not matter for a
                    #   project repo.
                    # - follow_symlinks, since for a git repo we should never
                    #   want to symlink to absolute paths.
                  };
                }
              )
            );
          };

          clobber-by-default = lib.mkOption {
            description = ''
              Whether files should be overwritten by default.
            '';
            type = types.nullOr types.bool;
          };
        };

        smfhPackage = lib.mkOption {
          description = ''
            The smfh package to use.
          '';
          default = pkgs.smfh;
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
              ${lib.getExe cfg.smfhPackage} --impure diff ${new-manifest} .config/filegen-manifest.json
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
