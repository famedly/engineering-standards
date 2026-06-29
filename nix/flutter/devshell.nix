{ lib, ... }: importingFlake: {
  perSystem = { config, pkgs, ... }: {
    devshells.flutter = {
      packages = [ pkgs.flutter ];

      # Inherit the standards commands (prek, filegen helpers, etc.)
      # Filter out "menu" to avoid duplicate entries when shells are composed.
      commands = lib.filter (command: command.name != "menu") config.devshells.standards.commands;
    };
  };
}
