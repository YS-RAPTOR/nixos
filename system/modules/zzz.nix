{ settings, ... }:
{
  imports = [
    ./auto-update.nix
    ./bluetooth.nix
    ./boot.nix
    ./envfs.nix
    ./gpg.nix
    ./hyprland.nix
    ./login.nix
    ./nvidia.nix
    ./pipewire.nix
    ./raptor.nix
    ./startup.nix
    ./stylix.nix
    ./time-locale.nix
  ];
}
