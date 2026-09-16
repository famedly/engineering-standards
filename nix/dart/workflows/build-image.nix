## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Places the expression the image workflows evaluate. It is one file for the
# whole repository: which project and which artefact it is called for arrives
# in the environment, so a repository shipping four images still has one copy
# of how an image gets built.
{
  config,
  lib,
  standardsLib,
  ...
}:
let
  inherit (standardsLib.imageWorkflow { inherit config; }) buildImage;
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.famedly.standards.dart) projects;
    in
    lib.mkIf
      (
        standardsLib.featureProjects "image" projects != { }
        || standardsLib.webProjects "image" projects != { }
      )
      {
        filegen.settings.files = [
          {
            type = "copy";
            target = buildImage.target;

            source = standardsLib.managedFile {
              inherit pkgs;

              name = "build-image.nix";
              file = buildImage.source;

              note = ''
                The workflows that call this pass what it reads in the
                environment, so it takes no arguments and is not useful to
                evaluate by hand.
              '';
            };
          }
        ];
      };
}
