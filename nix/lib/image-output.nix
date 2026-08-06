## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# An image here is a function, not a derivation: the artefact it wraps — a
# compiled binary, a built site — exists only once CI has produced it, because
# resolving our private dependencies needs credentials a build sandbox does not
# have. `packages` rejects anything that is not a derivation, so each kind of
# image gets a flake output of its own, transposed out of `perSystem` the same
# way flake-parts transposes `packages` and `devShells`.
#
# `nix flake check` calls such an output unknown, since it only knows the
# schema's own names. That warning is the price of the outputs saying what they
# hold; the alternative is `legacyPackages`, whose name is nixpkgs' history and
# describes nothing about us.
{ lib, flake-parts-lib }:
{
  name,
  file,
  description,
}:
flake-parts-lib.mkTransposedPerSystemModule {
  inherit name file;

  option = lib.mkOption {
    inherit description;
    type = lib.types.lazyAttrsOf (lib.types.functionTo lib.types.package);
    default = { };
  };
}
