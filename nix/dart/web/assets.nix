# The files a web build needs in `web/` before it starts, and which are not
# checked in: the vodozemac WebAssembly module, and the worker that encrypts
# media frames. Both are compiled artefacts of dependencies, so a repository
# that carried them would carry a copy that silently ages.
#
# One script does it, and both CI and a developer's shell run that same script —
# an asset that only CI knows how to produce is one a developer cannot reproduce
# when the site misbehaves in the browser.
{ lib, flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.famedly.standards.dart.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.web.livekitE2eeWorker.enable = lib.mkEnableOption ''
              compiling LiveKit's end-to-end encryption worker into `web/`.

              `dart_webrtc` starts it by name from the site root, and without it
              a call joins but carries no media. It is compiled from the
              `livekit_client` package the project already resolved, so it
              follows `pubspec.lock` and needs no pin of its own.

              The compiler leaves `web/e2ee.worker.dart.js` and two files beside
              it; the project's `.gitignore` has to cover them
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
      ...
    }:
    let
      inherit (import ../../lib/project-paths.nix { inherit lib; }) directory suffix;

      script = import ../../lib/compose-script.nix { inherit lib; };

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
              # Runnable from anywhere in the repository, since a developer who
              # wants these files is rarely standing in the project's root.
              ''cd "$(git rev-parse --show-toplevel)/${directory project}"''
            ]
            ++ lib.optional projectConfig.vodozemac.enable ''
              # `pkg/` is where `vod.init` looks unless it is told otherwise, so
              # an application needs to say nothing for these to be found.
              install -Dm644 -t web/pkg ${self'.packages.famedly-vodozemac-web}/*
            ''
            ++ lib.optional projectConfig.web.livekitE2eeWorker.enable ''
              # The worker's own imports resolve through the project's package
              # config, which is also where the package it lives in is recorded.
              [ -f .dart_tool/package_config.json ] || flutter pub get

              package="$(jq -er '
              	.packages[] | select(.name == "livekit_client") | .rootUri
              ' .dart_tool/package_config.json)"

              dart compile js --minify \
              	--packages=.dart_tool/package_config.json \
              	--output web/e2ee.worker.dart.js \
              	"''${package#file://}/web/e2ee.worker.dart"
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
