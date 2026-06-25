{ flake-parts-lib, lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { pkgs, ... }:
    {
      options.famedly.standards.rust.projects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.rustfmt.settings = lib.mkOption {
              inherit (pkgs.formats.toml { }) type;

              description = ''
                Settings to write to the projects' `rustfmt.toml`.
              '';

              default = { };
            };

            config.rustfmt.settings = {
              edition = lib.mkDefault "2024";
              style_edition = lib.mkDefault "2024";

              hard_tabs = lib.mkDefault true;
              max_width = lib.mkDefault 100;

              # Rustfmt will normally reflow e.g. long list
              # definitions, even if they don't max out to the full
              # width. This makes it so rustfmt only reflows lines
              # that overflow the set line width.
              use_small_heuristics = lib.mkDefault "Max";

              # Import resorting and grouping (unstable as of v1.9)
              group_imports = lib.mkDefault "StdExternalCrate";
              imports_granularity = lib.mkDefault "Crate";

              # Comment formatting (unstable as of v1.9)
              wrap_comments = lib.mkDefault true;
              comment_width = lib.mkDefault 80;
              doc_comment_code_block_width = lib.mkDefault 80;
              format_code_in_doc_comments = lib.mkDefault true;
            };
          }
        );
      };
    }
  );

  config.perSystem =
    {
      config,
      pkgs,
      self',
      ...
    }:
    {
      treefmt.programs.rustfmt = {
        enable = true;
        package = self'.packages.famedly-rust-toolchain;
      };

      filegen.settings.files = map (
        { name, value }:
        {
          type = "copy";
          target = "${name}/rustfmt.toml";
          source = pkgs.writers.writeTOML "rustfmt.toml" value.rustfmt.settings;
        }
      ) (lib.attrsToList config.famedly.standards.rust.projects);
    };
}
