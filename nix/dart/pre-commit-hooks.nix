{ lib, ... }:
{
  config.perSystem =
    {
      config,
      pkgs,
      ...
    }:
    let
      projects = config.famedly.standards.dart.projects;

      inherit (import ./project-paths.nix { inherit lib; }) directory;

      # Forgetting the `include` is silent: `dart analyze` then simply analyzes
      # with the default rule set and reports nothing about it.
      lints-included = pkgs.writeShellApplication {
        name = "dart-lints-included";
        runtimeInputs = [ pkgs.gnugrep ];

        text = ''
          status=0

          check() {
            managed="$1"
            own="$2"

            if [ ! -f "$own" ]; then
              printf 'error: %s does not exist.\n' "$own"
            elif ! grep -qE "^include:[[:space:]]*(\./)?$managed([[:space:]]|$)" "$own"; then
              printf 'error: %s does not include the managed lints.\n' "$own"
            else
              return 0
            fi

            printf '       Without it the standard rule set has no effect. Add:\n\n         include: %s\n\n' "$managed"
            status=1
          }

          ${lib.concatLines (
            lib.mapAttrsToList (
              project: _: ''check analysis_options.standards.yaml "${directory project}analysis_options.yaml"''
            ) projects
          )}
          exit "$status"
        '';
      };

      hook = drv: description: {
        id = drv.meta.mainProgram;
        name = drv.meta.mainProgram;
        inherit description;

        entry = drv.meta.mainProgram;
        # The checks are about files that may be absent, so they can't be driven
        # by the changed file list.
        pass_filenames = false;

        language = "system";
      };
    in
    lib.mkIf (projects != { }) {
      prek-pre-commit = {
        package.runtimePkgs = [ lints-included ];

        workspaces.".".repos = [
          {
            repo = "local";

            hooks = [
              (hook lints-included "Ensure the managed Dart lints are actually included")
            ];
          }
        ];
      };
    };
}
