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

                  };
                }
              )
            );
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
      checks.check-filegen = pkgs.runCommand "check-filegen" { } (
        "touch $out;\n"
        + pkgs.lib.concatStringsSep "\n" (
          builtins.map (fgfile: "cmp ${fgfile.source} ${../../.}/${fgfile.target}") cfg.settings.files
        )
      );
      apps =
        let
          filegen-activate = pkgs.writeShellApplication {
            name = "filegen-activate";
            text = pkgs.lib.concatStringsSep "\n" (
              builtins.map (fgfile: "cat ${fgfile.source} > ./${fgfile.target}") cfg.settings.files
            );
          };
        in
        {
          filegen-activate = {
            program = lib.getExe filegen-activate;
            meta = {
              description = "Install files defined by the `filegen` options of this flake";
              package = filegen-activate;

            };
          };
        };
    };
}
