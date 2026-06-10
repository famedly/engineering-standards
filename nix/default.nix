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

  flake.lib.famedlySystems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  # TODO: Break this out into a proper ecosystem-oriented module.
  perSystem = { pkgs, lib, ... }: {
    devshells.k8s.packages = lib.attrValues { inherit (pkgs) kubectl kubelogin-oidc kubetui; };
  };
}
