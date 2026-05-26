{
  flakeModules,
  inputs,
  importApply,
  ...
}@args:
importingFlake: {
  imports = [
    inputs.devshell.flakeModule
    inputs.github-actions-nix.flakeModules.default
    flakeModules.prek-pre-commit

    (importApply ./general args)

    (importApply ./dart args)
    (importApply ./nix args)
    (importApply ./python args)
    (importApply ./rust args)
  ];
}
