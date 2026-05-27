{ inputs, importApply, ... }@args:
importingFlake: {
  imports = [
    (importApply ./general args)
    (importApply ./rust args)
  ];
}
