## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The Dart standards evaluate almost entirely inside `config.perSystem`, and
# this repository configures no Dart project of its own — so nothing here ever
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
      # repository's — which is the whole difference between evaluating the
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
      images = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        (config.dartImages."." { server = ./files/config.yaml; })
        (config.dartWebImages."./app" { site = ./files; })
      ];
    in
    {
      # Flutter is not packaged everywhere, and the fixture holds a Flutter
      # project on purpose.
      checks = lib.optionalAttrs (self'.packages ? famedly-flutter-sdk) {
        dart-standards = generated.overrideAttrs (old: {
          buildCommand = lib.concatStringsSep "\n" (
            map (image: "echo ${image.drvPath} >/dev/null") images ++ [ old.buildCommand ]
          );
        });
      };
    };
}
