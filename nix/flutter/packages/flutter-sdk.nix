{
  flutterPackages,
  lib,
}:

let
  data = lib.importJSON ./data.json;
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
