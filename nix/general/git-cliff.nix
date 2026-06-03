importingFlake: {
  perSystem =
    { ... }:
    {
      filegen.settings.files = [
        {
          type = "copy";
          target = "./cliff.toml";
          source = ../../standards/cliff.toml;
          clobber = true;
        }
      ];
    };
}
