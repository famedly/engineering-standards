# Applies this repository's image function for one project to the artefact a
# workflow run has just built.
#
# Every image workflow of ours calls this with `nix build --impure --file`.
# What it asks for changes from run to run — which project, which artefact,
# which commit — and it arrives in the environment rather than as arguments,
# because an expression that took arguments would have to be assembled as text
# by whatever called it. Being assembled as text is what this file replaces.
let
  # This file sits beside the workflows that call it, so everything it names
  # lives in the checkout one directory up.
  root = ./..;

  flake = builtins.getFlake (toString root);

  # Missing values would otherwise surface as an image built without a version
  # or as an error naming an attribute nobody wrote.
  required =
    name:
    let
      value = builtins.getEnv name;
    in
    if value != "" then value else throw "${name} is unset; this is meant to be called from a workflow";

  images = builtins.getAttr builtins.currentSystem (builtins.getAttr (required "IMAGE_OUTPUT") flake);
in
builtins.getAttr (required "IMAGE_PROJECT") images {
  # Named after the argument it fills: a server image is handed a compiled
  # binary, a web image the directory of files it is to serve.
  ${required "IMAGE_ARTEFACT"} = root + "/${required "IMAGE_PATH"}";

  # What the run knows about where the image came from. Filled in here rather
  # than asked of every workflow, so that no image of ours ships unlabelled.
  source = required "IMAGE_SOURCE";
  revision = required "IMAGE_REVISION";
  version = required "IMAGE_VERSION";
}
