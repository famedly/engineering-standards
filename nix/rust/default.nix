{
  flake-parts-lib,
  lib,
  importApply,
  ...
}:
importingFlake: {
  imports = [ ];

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
