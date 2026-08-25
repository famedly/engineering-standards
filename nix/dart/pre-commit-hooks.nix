## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: {
  config.perSystem =
    {
      config,
      pkgs,
      self',
      standardsLib,
      ...
    }:
    let
      inherit (standardsLib) directory;

      projects = config.famedly.standards.dart.projects;

      usesVodozemac = lib.any (project: project.vodozemac.enable) (lib.attrValues projects);

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

      # A line that is nothing but a statement behind `//` is code somebody
      # meant to come back to. It stops being compiled, so it stops being
      # updated, and it decays into a claim about the code that is no longer
      # true — while git remembers it perfectly well without the help.
      commented-out-code = pkgs.writeShellApplication {
        name = "dart-no-commented-out-code";
        runtimeInputs = [ pkgs.gnugrep ];

        text = ''
          # Without files grep would read stdin and hang, which is what a hook
          # invoked on a commit that touches no Dart looks like.
          if [ "$#" -eq 0 ]; then
            exit 0
          fi

          # `//<` is left alone: that is how an editor's region markers start.
          if grep -nE '^[[:space:]]*//[^/<].*;[[:space:]]*$' "$@"; then
            printf '\nerror: the lines above are commented-out Dart code.\n'
            printf '       Delete them — git has them if you want them back.\n\n'
            exit 1
          fi
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

          # Either name will do: both are cut from the tag this checks.
          check() {
            pubspec="$1"
            found="$(sed -n 's/^[[:space:]]*\(flutter_\)\{0,1\}vodozemac:[[:space:]]*[^0-9]*\([0-9][0-9.]*\).*/\2/p' "$pubspec" | head -n1)"

            if [ -z "$found" ]; then
              printf 'error: no plain vodozemac or flutter_vodozemac version constraint found in %s.\n' "$pubspec"
            elif [ "$found" != "$wanted" ]; then
              printf 'error: %s constrains vodozemac to %s, but the nix bindings are %s.\n' "$pubspec" "$found" "$wanted"
            else
              return 0
            fi

            printf '       Both are released together and have to match. Either bump the\n'
            printf '       constraint, or bump nix/dart/vodozemac/source.nix in the\n'
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
        package.runtimePkgs = [
          commented-out-code
          lints-included
        ]
        ++ lib.optional usesVodozemac vodozemac-version;

        workspaces.".".repos = [
          {
            repo = "local";

            hooks = [
              (hook lints-included "Ensure the managed Dart lints are actually included")

              # Unlike the checks above this one is about the files in the
              # commit, so it takes them and stays cheap on a large repository.
              (
                hook commented-out-code "Reject commented-out Dart code"
                // {
                  pass_filenames = true;
                  files = ''\.dart$'';
                }
              )
            ]
            ++ lib.optional usesVodozemac (
              hook vodozemac-version "Ensure the vodozemac constraint matches the nix bindings"
            );
          }
        ];
      };
    };
}
