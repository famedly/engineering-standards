## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The workflow and the artefact that carry a project's web target are named in
# one place, since the build job and every destination job have to agree on both
# and a rename would otherwise break the wiring silently.
{ lib }:
let
  inherit (import ../../lib/project-paths.nix { inherit lib; }) suffix;
in
{
  workflowId = project: "dart-web${suffix project}";

  artifact = project: "web${suffix project}";
}
