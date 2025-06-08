{ config, pkgs, pkgs-stable, userSettings, systemSettings, inputs, ... }:

{
  imports = [ ./modules/zzz.nix ];

  # user setup
  home.username = userSettings.username;
  home.homeDirectory = userSettings.homeDir;
  home.packages = [
    inputs.zen-browser.packages."${systemSettings.system}".default

  ];

  # NeoVim setup
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${userSettings.dotfilesDir}/nvim";
  xdg.configFile."dictionary".source = config.lib.file.mkOutOfStoreSymlink
    "${userSettings.dotfilesDir}/dictionary";

  # Environment Variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.stateVersion = "25.05"; # Please read the comment before changing.
  programs.home-manager.enable = true;
}
