## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The options both kinds of image take: what it is called, where it is pushed,
# who it runs as, and which runner builds it.
#
# They were declared once per image module, and the copies had already begun to
# differ in wording where they did not differ in behaviour — the port was the
# service's in one and the server's in the other, and the amd64 runner built an
# image in one and assembled it in the other.
#
# `image-workflow.nix` already assumed the shape was shared: `reference` takes
# `{ name, nightlyRegistry, releaseRegistry, ... }` and is called with both.
# This is that assumption written down.
{ lib, flake-parts-lib, ... }:
let
  shared =
    {
      # An image's gid follows its uid, and an option whose default is another
      # option has to name it rather than show its value.
      uid,
      uidPath,
    }:
    {
      name = lib.mkOption {
        description = "Name of the image to push, without the registry.";
        type = lib.types.str;
        example = "famedly-headless";
      };

      port = lib.mkOption {
        description = "Port the service in the image listens on.";
        type = lib.types.port;
        default = 8080;
      };

      user = {
        uid = lib.mkOption {
          description = "Uid the service in the image runs as.";
          type = lib.types.int;
          default = 10001;
        };

        gid = lib.mkOption {
          description = "Gid the service in the image runs as.";
          type = lib.types.int;
          default = uid;
          defaultText = uidPath;
        };
      };

      nightlyRegistry = lib.mkOption {
        description = "Registry images built from pull requests go to.";
        type = lib.types.str;
        default = "registry.famedly.net/docker-nightly";
      };

      releaseRegistry = lib.mkOption {
        description = ''
          Registry images built from `main` and version tags go to.
        '';
        type = lib.types.str;
        default = "registry.famedly.net/docker-releases";
      };

      # Only the amd64 runner is the same choice for both. What to build arm64
      # on depends on how much of the build is compilation, which is where the
      # two kinds of image differ, so each names its own.
      runners.amd64 = lib.mkOption {
        description = "Runner that builds the amd64 image.";
        type = lib.types.str;
        default = "ubuntu-latest";
      };
    };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }: {
            options.image = shared {
              uid = config.image.user.uid;
              uidPath = "config.image.user.uid";
            };

            options.web.image = shared {
              uid = config.web.image.user.uid;
              uidPath = "config.web.image.user.uid";
            };
          }
        )
      );
    };
  });
}
