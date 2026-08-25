## SPDX-FileCopyrightText: 2026 Famedly GmbH
##
## SPDX-License-Identifier: Apache-2.0

# Adds fields to `famedly.standards.dart.projects.<path>`.
#
# Every feature here declares its own options on that submodule, and the module
# system merges them. This is the five lines of scaffolding that stand between
# a flake-parts module and those options, written once.
#
# Called from a module's `imports`, so it takes `lib` and `flake-parts-lib`
# directly: `_module.args` does not exist yet at that point.
{ lib, flake-parts-lib }: submodule: {
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.famedly.standards.dart.projects = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule submodule);
    };
  };
}
