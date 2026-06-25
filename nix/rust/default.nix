{
  flake-parts-lib,
  lib,
  importApply,
  ...
}@args:
importingFlake: {
  imports = [
    (importApply ./devshell.nix args)
    (importApply ./formatting.nix args)
    (importApply ./toolchain.nix args)
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.rust.projects = lib.mkOption {
      description = ''
        Rust projects in the repository that should be equipped with our
        standards.

        This must be a relative path starting with `.`. Simply use `.` if the
        whole project is a Rust project.
      '';
      default = { };

      example = ''
        {
          "." = { };
        }
      '';

      type = lib.types.attrsOf (lib.types.submodule { });
    };
  });
}
