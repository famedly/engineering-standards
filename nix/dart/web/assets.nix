## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The files a web build needs in `web/` before it starts: the vodozemac
# WebAssembly module, and the worker that encrypts media frames. Both are
# compiled artefacts of dependencies, so a checked-in copy would silently age.
#
# CI and a developer's shell run the same script, so an asset that misbehaves
# in the browser can be reproduced outside CI.
{ lib, flake-parts-lib, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }: {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.web.livekitE2eeWorker.enable = lib.mkEnableOption ''
              compiling LiveKit's end-to-end encryption worker into `web/`.

              `dart_webrtc` starts it by name from the site root, and without
              it a call joins but carries no media. Compiled from the
              `livekit_client` the project already resolved, so it needs no pin
              of its own.

              Leaves `web/e2ee.worker.dart.js`, which the project's
              `.gitignore` has to cover
            '';
          }
        );
      };
    }
  );

  config.perSystem =
    {
      config,
      pkgs,
      self',
      standardsLib,
      ...
    }:
    let
      inherit (standardsLib) directory script suffix;

      projects = lib.filterAttrs (
        _: project: project.web.enable && (project.vodozemac.enable || project.web.livekitE2eeWorker.enable)
      ) config.famedly.standards.dart.projects;

      mkAssets =
        project: projectConfig:
        pkgs.writeShellApplication {
          name = "dart-web-assets${suffix project}";

          runtimeInputs = [
            config.famedly.standards.dart.toolchain
            pkgs.coreutils
            pkgs.git
            pkgs.jq
          ];

          text = script (
            [
              # Runnable from anywhere in the repository.
              ''cd "$(git rev-parse --show-toplevel)/${directory project}"''
            ]
            ++ lib.optional projectConfig.vodozemac.enable ''
              # Where `vod.init` looks unless an application says otherwise.
              install -Dm644 -t web/pkg ${self'.packages.famedly-vodozemac-web}/*
            ''
            ++ lib.optional projectConfig.web.livekitE2eeWorker.enable ''
              # The worker's imports resolve through the project's package config,
              # which also records where the package itself sits.
              [ -f .dart_tool/package_config.json ] || flutter pub get

              package="$(jq -er '
              	.packages[] | select(.name == "livekit_client") | .rootUri
              ' .dart_tool/package_config.json)"

              # Flutter copies everything under `web/` into the site, so what
              # the compiler leaves beside the worker is served with it: a map
              # hands out the source it was compiled from, and the dependency
              # list beside it can only be deleted, not turned off.
              dart compile js --minify --no-source-maps \
              	--packages=.dart_tool/package_config.json \
              	--output web/e2ee.worker.dart.js \
              	"''${package#file://}/web/e2ee.worker.dart"

              rm -f web/e2ee.worker.dart.js.deps
            ''
          );
        };
    in
    {
      packages = lib.mapAttrs' (
        project: projectConfig:
        lib.nameValuePair "dart-web-assets${suffix project}" (mkAssets project projectConfig)
      ) projects;

      devshells.standards.packages = lib.mapAttrsToList (
        project: _: self'.packages."dart-web-assets${suffix project}"
      ) projects;
    };
}
