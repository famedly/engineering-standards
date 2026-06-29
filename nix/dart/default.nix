{
  flake-parts-lib,
  lib,
  importApply,
  ...
}@args:
importingFlake: {
  imports = [
    (importApply ./devshell.nix args)
    (importApply ./pre-commit-hooks.nix args)
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      description = ''
        Dart projects in the repository that should be equipped with our
        standards.

        This must be a relative path starting with `.`. Simply use `.` if the
        whole project is a Dart project.
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
