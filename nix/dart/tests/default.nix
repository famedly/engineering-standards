## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The Dart standards evaluate almost entirely inside `config.perSystem`, and
# this repository configures no Dart project of its own, so nothing here ever
# ran any of it until a downstream repository did. This evaluates the standards
# against a fixture repository the way a downstream flake would, and collects
# everything they generate into one directory.
#
# `nix build .#checks.<system>.dart-standards` then gives a tree that can be
# diffed across a change: a refactor that is meant to keep the output identical
# has to produce the same bytes, and one that is not shows exactly what moved.
#
# Imported by this repository's own `flake.nix` rather than by
# `nix/dart/default.nix`, so downstream flakes do not carry the check.
{ inputs, self, ... }: {
  perSystem =
    {
      lib,
      pkgs,
      self',
      system,
      ...
    }:
    let
      # The fixture is a flake in its own right, so that `self'` inside the
      # standards resolves to the fixture's packages rather than to this
      # repository's. That is the whole difference between evaluating the
      # modules and evaluating how a project uses them.
      evaluated =
        inputs.flake-parts.lib.evalFlakeModule
          {
            inputs = inputs // {
              self = fixture;
            };
          }
          {
            systems = [ system ];
            imports = [
              self.flakeModules.default
              ./projects.nix
            ];
          };

      fixture = evaluated.config.processedFlake // {
        _type = "flake";
        inherit (self) outPath;
        inputs = inputs // {
          self = fixture;
        };
      };

      config = evaluated.config.allSystems.${system};

      # Everything the standards would write into the fixture repository:
      # workflows, lint configuration, pre-commit hooks. Their targets are
      # repository-relative, so the tree mirrors what the checkout would look
      # like.
      generated = pkgs.runCommand "dart-standards-fixture" { } ''
        ${lib.concatMapStringsSep "\n" (
          file: ''install -Dm644 ${file.source} "$out/${file.target}"''
        ) config.filegen.settings.files}
      '';

      # The images are functions rather than files, so they are not part of the
      # tree above. Forcing their derivations is what makes a mistake in them
      # fail here instead of in the first repository to build one.
      #
      # Only on Linux: an image holds a glibc, which nixpkgs refuses to evaluate
      # for a darwin host. CI builds them on Linux runners either way.
      #
      # One is given what CI knows about the commit and the other is not, so
      # that both shapes an image is called with are covered.
      images = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        (config.dartImages."." {
          server = ./files/config.yaml;

          source = "https://github.com/famedly/fixture";
          revision = "0000000000000000000000000000000000000000";
          version = "v1.0.0";
        })

        (config.dartWebImages."./app" { site = ./files; })
      ];

      # A generated `run:` script is the one part of a workflow that nothing
      # else looks at. The Nix assembling it is formatted, evaluated and
      # diffed, and a mistake inside the string it produces survives all of
      # that to fail on a runner minutes into a job.
      #
      # actionlint validates the workflow around it and hands every script to
      # shellcheck, substituting the `${{ }}` expressions first — which is why
      # it can check scripts that are not valid shell as they are written.
      lintedWorkflows =
        pkgs.runCommand "dart-standards-workflows"
          {
            nativeBuildInputs = [
              pkgs.actionlint
              pkgs.git
              pkgs.nixfmt
            ];

            # SC2016 fires on the backticks our error annotations put around
            # the command they tell the reader to run. They are prose.
            SHELLCHECK_OPTS = "-e SC2016";
          }
          ''
            cp -r ${generated} repository
            chmod -R u+w repository
            cd repository

            # A gate is a workflow the repository using the standards writes
            # and names in its configuration, so the fixture generates a
            # reference to one that isn't there. actionlint resolves those.
            cat >.github/workflows/test.yaml <<'EOF'
            on:
              workflow_call: {}
            jobs:
              test:
                runs-on: ubuntu-latest
                steps:
                  - run: "true"
            EOF

            # actionlint finds the workflows relative to the repository root,
            # and finds the root by looking for this.
            git init -q .

            actionlint

            # The expression the image workflows evaluate is copied into the
            # repository rather than imported by anything, so nothing else
            # reads it before a runner does. The formatter has to parse it to
            # have an opinion, which is the half of this that matters.
            nixfmt --check .github/build-image.nix

            touch $out
          '';

      # Nothing runs `nix flake check` for this repository — its one workflow
      # runs the pre-commit hooks and nothing else — so the checks above would
      # be run by whoever thought to run them. This puts them where CI already
      # looks, on the stage this module reserves for work too slow to do on
      # every commit.
      #
      # It costs an evaluation rather than a build: the images are only
      # instantiated, and everything else here is text.
      runChecks = pkgs.writeShellApplication {
        name = "dart-standards-fixture";

        text = ''
          nix build --no-link --print-build-logs \
          	".#checks.${system}.dart-standards" \
          	".#checks.${system}.dart-standards-workflows"
        '';
      };
    in
    # Flutter is not packaged everywhere, and the fixture holds a Flutter
    # project on purpose.
    lib.mkIf (self'.packages ? famedly-flutter-sdk) {
      checks = {
        dart-standards = generated.overrideAttrs (old: {
          buildCommand = lib.concatStringsSep "\n" (
            map (image: "echo ${image.drvPath} >/dev/null") images ++ [ old.buildCommand ]
          );
        });

        dart-standards-workflows = lintedWorkflows;
      };

      prek-pre-commit = {
        package.runtimePkgs = [ runChecks ];

        workspaces.".".repos = [
          {
            repo = "local";

            hooks = [
              {
                id = "dart-standards";
                name = "dart standards";
                description = "Evaluate the Dart standards against the fixture repository";

                entry = "dart-standards-fixture";
                pass_filenames = false;
                stages = [ "pre-push" ];

                language = "system";
              }
            ];
          }
        ];
      };
    };
}
