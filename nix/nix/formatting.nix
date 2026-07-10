{
  perSystem.treefmt = {
    programs.nixfmt.enable = true;
    settings.formatter.nixfmt = {
      command = "nixfmt";
      options = [ "--strict" ];
    };
  };
}
