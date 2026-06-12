{
  flake-parts-lib,
  importApply,
  lib,
  ...
}@args:
importingFlake: {
  imports = [ (importApply ./sdk.nix args) ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.flutter.projects = lib.mkOption {
      description = ''
        Flutter projects in the repository that should be equipped with our
        standards.

        This must be a relative path starting with `.`. Simply use `.` if the
        whole project is a Flutter project.
      '';
      default = { };

      example = ''
        {
          "." = { };
          "./example" = { };
        }
      '';

      type = lib.types.attrsOf (lib.types.submodule { });
    };
  });
}
