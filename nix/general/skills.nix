_: {
  perSystem =
    { lib, ... }:
    let
      skillsSrc = ../../llm/skills;
      prefix = "${toString skillsSrc}/";
    in
    {
      # Distribute the vendored agent skills into every environment under the
      # cross-client `.agents/skills/` directory. smfh's `copy` only accepts
      # file sources, so we emit one entry per file; parent directories are
      # created automatically during activation.
      filegen.settings.files = map (file: {
        type = "copy";
        target = "./.agents/skills/${lib.removePrefix prefix (toString file)}";
        source = file;
        clobber = true;
      }) (lib.filesystem.listFilesRecursive skillsSrc);
    };
}
