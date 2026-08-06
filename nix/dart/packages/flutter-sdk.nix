## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0
{ flutterPackages, lib }:

let
  data = lib.importJSON ./flutter-sdk-data.json;
in
(flutterPackages.wrapFlutter (
  flutterPackages.mkFlutter (
    data
    // {
      patches = [ ];
      enginePatches = [ ];
    }
  )
)).overrideAttrs
  (old: {
    pname = "famedly-flutter-sdk";
    name = "famedly-flutter-sdk-${data.version}";
  })
