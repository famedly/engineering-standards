importingFlake: {
  perSystem =
    { lib, pkgs, ... }:
    {
      devshells.general.packages = lib.attrValues { inherit (pkgs) prek; };

      filegen.settings.files = [
        {
          type = "copy";
          target = "./.envrc";
          source = pkgs.writeText ".envrc" ''
            use flake .#general
          '';
          clobber = true;
        }
      ];
    };
}
