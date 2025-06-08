{ pkgs, pkgs-stable }:
let
  default-packages = with pkgs; [
    neovim
    google-chrome
    ghostty
    waybar
    git
    home-manager
    bat
    fish
    tmux
    yazi
    fzf
    ripgrep
    grep
    eza

    # utils
    unzip
    lazygit
    zoxide
    direnv
    oh-my-posh
    pass
    git-credential-manager

    # programming languages
    gcc
    zig
    nodejs
    go
    dotnet-sdk
    rustup
    uv

    # Delete Later
    kitty
  ];

  # If there are problems with the unstable branch
  stable-packages = with pkgs-stable; [ ];

in {
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = default-packages ++ stable-packages;
}
