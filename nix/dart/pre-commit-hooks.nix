## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ lib, ... }: {
  perSystem =
    {
      config,
      pkgs,
      self',
      standardsLib,
      ...
    }:
    let
      inherit (config.famedly.standards.dart) projects;

      usesVodozemac = lib.any (project: project.vodozemac.enable) (lib.attrValues projects);

      # Forgetting the `include` is silent, `dart analyze` just falls back to
      # the default rule set without telling anyone.
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
              project: _: ''check analysis_options.standards.yaml "${project}/analysis_options.yaml"''
            ) projects
          )}
          exit "$status"
        '';
      };

      # The managed lint configuration references packages the project has to
      # resolve itself. A constraint that is missing or too old surfaces as an
      # analysis error about a plugin, which reads as the analyzer's problem
      # rather than the manifest's — and a rule set that fails to load is
      # silently no rule set at all.
      lint-packages = pkgs.writeShellApplication {
        name = "dart-lint-packages";
        runtimeInputs = [ pkgs.yq-go ];

        text = ''
          status=0

          check() {
            pubspec="$1"
            package="$2"
            wanted="$3"

            # A manifest is YAML, so a YAML parser reads it. A regex would
            # answer for a package named in a comment or under the wrong
            # section.
            found="$(PACKAGE="$package" yq -r '.dev_dependencies[strenv(PACKAGE)] // ""' "$pubspec")"

            if [ -z "$found" ]; then
              printf 'error: %s declares no dev dependency on %s.\n' "$pubspec" "$package"
            elif [ "$found" != "$wanted" ]; then
              printf 'error: %s constrains %s to %s, but the managed lints need %s.\n' \
                "$pubspec" "$package" "$found" "$wanted"
            else
              return 0
            fi

            printf '       analysis_options.standards.yaml is generated against that version.\n'
            printf '       Either declare it, or change what the flake asks of this project.\n\n'
            status=1
          }

          ${lib.concatLines (
            lib.concatLists (
              lib.mapAttrsToList (
                project: projectConfig:
                lib.mapAttrsToList (
                  package: settings:
                  "check ${lib.escapeShellArg "${project}/pubspec.yaml"} ${package} ${lib.escapeShellArg settings.constraint}"
                ) projectConfig.linting.packages
              ) projects
            )
          )}
          exit "$status"
        '';
      };

      # Code behind `//` stops being compiled, so it stops being updated and
      # turns into a claim that isn't true anymore. Git still has it if
      # anyone wants it back.
      commented-out-code = pkgs.writeShellApplication {
        name = "dart-no-commented-out-code";
        runtimeInputs = [ pkgs.gnugrep ];

        text = ''
          # Without files grep would read stdin and hang.
          if [ "$#" -eq 0 ]; then
            exit 0
          fi

          # We leave `//<` alone, that's how editor region markers start.
          if grep -nE '^[[:space:]]*//[^/<].*;[[:space:]]*$' "$@"; then
            printf '\nerror: the lines above are commented-out Dart code.\n'
            printf '       Delete them — git has them if you want them back.\n\n'
            exit 1
          fi
        '';
      };

      # The bindings and the Dart package are released together. If the
      # constraint drifts nothing fails at build time, only at the first call.
      vodozemac-version = pkgs.writeShellApplication {
        name = "dart-vodozemac-version";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnused
        ];

        text = ''
          status=0
          wanted="${self'.packages.famedly-vodozemac.version}"

          # Either name will do, since both are cut from the tag we check.
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
            lib.mapAttrsToList (project: _: ''check "${project}/pubspec.yaml"'') (
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
        # These check for files that may be absent.
        pass_filenames = false;

        language = "system";
      };
    in
    lib.mkIf (projects != { }) {
      prek-pre-commit = {
        package.runtimePkgs = [
          commented-out-code
          lint-packages
          lints-included
        ]
        ++ lib.optional usesVodozemac vodozemac-version;

        workspaces.".".repos = [
          {
            repo = "local";

            hooks = [
              (hook lints-included "Ensure the managed Dart lints are actually included")

              (hook lint-packages "Ensure the projects declare the lint packages the managed configuration needs")

              # This one gets the commit's files, which keeps it cheap on a
              # large repository.
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
