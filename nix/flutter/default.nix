{
  flake-parts-lib,
  lib,
  importApply,
  ...
}@args:
importingFlake: {
  imports = [
    (importApply ./devshell.nix args)
    ./workflows/flutter-ci.nix
  ];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.flutter.projects = lib.mkOption {
      description = ''
        Flutter projects in the repository that should be equipped with our
        standards.

        This must be a relative path starting with `.`. Simply use `.` if the
        whole project is a Flutter project.

        Note: Flutter projects should also configure
        `famedly.standards.dart.projects` to enable the dart format pre-commit
        hook, since the dart module owns that hook.
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
