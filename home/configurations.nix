{ config, pkgs, pkgs-stable, userSettings, systemSettings, inputs, ... }:

{
  imports = [ ./modules/zzz.nix ];

  # user setup
  home.username = userSettings.username;
  home.homeDirectory = userSettings.homeDir;
  home.packages = [
    inputs.zen-browser.packages."${systemSettings.system}".default
    pkgs.wget
    pkgs.jq
    pkgs.wl-clipboard
    pkgs.networkmanager_dmenu
    pkgs.btop
    pkgs.pavucontrol
    pkgs.freeoffice
    pkgs.steam-run
  ];

  # NeoVim setup
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${userSettings.dotfilesDir}/nvim";
  xdg.configFile."dictionary".source = config.lib.file.mkOutOfStoreSymlink
    "${userSettings.dotfilesDir}/dictionary";
  xdg.configFile."waybar".source =
    config.lib.file.mkOutOfStoreSymlink "${userSettings.dotfilesDir}/waybar";
  # Environment Variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.stateVersion = "25.05"; # Please read the comment before changing.
  programs.home-manager.enable = true;
}
