{ lib, ... }:
{
  config.perSystem =
    {
      config,
      pkgs,
      self',
      ...
    }:
    let
      projects = config.famedly.standards.dart.projects;

      usesVodozemac = lib.any (project: project.vodozemac.enable) (lib.attrValues projects);

      inherit (import ../lib/project-paths.nix { inherit lib; }) directory;

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

      # The bindings and the Dart package are released as a pair, so a drifted
      # constraint means the Dart side talks to an API the library may not have.
      # Nothing surfaces that at build time — it would fail when a call is made.
      vodozemac-version = pkgs.writeShellApplication {
        name = "dart-vodozemac-version";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnused
        ];

        text = ''
          status=0
          wanted="${self'.packages.famedly-vodozemac.version}"

          check() {
            pubspec="$1"
            found="$(sed -n 's/^[[:space:]]*vodozemac:[[:space:]]*[^0-9]*\([0-9][0-9.]*\).*/\1/p' "$pubspec" | head -n1)"

            if [ -z "$found" ]; then
              printf 'error: no plain vodozemac version constraint found in %s.\n' "$pubspec"
            elif [ "$found" != "$wanted" ]; then
              printf 'error: %s constrains vodozemac to %s, but the nix bindings are %s.\n' "$pubspec" "$found" "$wanted"
            else
              return 0
            fi

            printf '       Both are released together and have to match. Either bump the\n'
            printf '       constraint, or bump nix/dart/packages/vodozemac.nix in the\n'
            printf '       engineering standards to the version this project needs.\n\n'
            status=1
          }

          ${lib.concatLines (
            lib.mapAttrsToList (project: _: ''check "${directory project}pubspec.yaml"'') (
              lib.filterAttrs (_: project: project.vodozemac.enable) projects
            )
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
        package.runtimePkgs = [ lints-included ] ++ lib.optional usesVodozemac vodozemac-version;

        workspaces.".".repos = [
          {
            repo = "local";

            hooks = [
              (hook lints-included "Ensure the managed Dart lints are actually included")
            ]
            ++ lib.optional usesVodozemac (
              hook vodozemac-version "Ensure the vodozemac constraint matches the nix bindings"
            );
          }
        ];
      };
    };
}
