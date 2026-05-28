{
  flakeModules,
  inputs,
  importApply,
  ...
}@args:
importingFlake: {
  imports = [
    inputs.devshell.flakeModule
    flakeModules.prek-pre-commit

    (importApply ./general args)
    (importApply ./rust args)
  ];
}
