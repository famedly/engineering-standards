# Flutter projects are configured through `famedly.standards.dart.projects` with
# `flutter = true`, because Flutter is Dart plus a framework and the two share
# nearly every option, lint rule and workflow step. This module only packages the
# SDK that the Dart toolchain then picks up.
{ importApply, ... }@args: importingFlake: { imports = [ (importApply ./sdk.nix args) ]; }
