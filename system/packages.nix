{ pkgs, pkgs-stable, ... }:
let
  default-packages = with pkgs; [
    neovim
    google-chrome
    ghostty
    git
    home-manager
    fish

    # utils
    yazi
    tmux
    bat
    fzf
    ripgrep
    eza
    fd
    unzip
    lazygit
    zoxide
    direnv
    oh-my-posh
    brightnessctl
    playerctl
    udiskie
    pkg-config

    # wm
    dunst
    kdePackages.dolphin
    waybar
    hyprpaper
    wofi
    vesktop
    hyprpicker
    cliphist
    hypridle
    hyprlock

    # programming languages
    gcc
    zig
    nodejs
    go
    dotnet-sdk
    rustup
    uv
  ];

  # If there are problems with the unstable branch
  stable-packages = with pkgs-stable; [ ];

in {
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = default-packages ++ stable-packages;
}
