{ inputs, importApply, ... }@args: importingFlake: { imports = [ (importApply ./rust args) ]; }
