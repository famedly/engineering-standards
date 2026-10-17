## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# The helpers the standards' own modules share, handed to every module as the
# `standardsLib` argument by `./module.nix`.
#
# They used to be imported file by file, which meant a dozen copies of
# `import ../../lib/project-paths.nix { inherit lib; }` whose relative paths had
# to be counted out by hand every time a module moved.
#
# `image-output.nix` is deliberately absent: it is called from a module's
# `imports`, which the module system resolves before `_module.args` exists.
{ lib }: {
  inherit (import ./project-paths.nix { inherit lib; }) directory suffix;

  script = import ./compose-script.nix { inherit lib; };

  managedFile = import ./managed-file.nix { inherit lib; };

  imageWorkflow = import ./image-workflow.nix { inherit lib; };

  ociLabels = import ./oci-labels.nix { inherit lib; };
}
