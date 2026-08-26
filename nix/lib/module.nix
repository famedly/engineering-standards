## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Makes `./default.nix` available as the `standardsLib` module argument, both to
# flake-level modules and to `perSystem` ones.
{ lib, ... }:
let
  standardsLib = import ./. { inherit lib; };
in
{
  _module.args = { inherit standardsLib; };

  perSystem = _: { _module.args = { inherit standardsLib; }; };
}
