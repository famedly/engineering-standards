{
  perSystem.treefmt = {
    programs.nixfmt.enable = true;
    settings.formatter.nixfmt.options = [ "--strict" ];
  };
}
