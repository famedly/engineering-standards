importingFlake: {
  perSystem =
    { ... }:
    {
      filegen.settings.files = [
        {
          type = "copy";
          target = "./.config/cliff.toml";
          source = ../../standards/cliff.toml;
          clobber = true;
        }
      ];
    };
}
