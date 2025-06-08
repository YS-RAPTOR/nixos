{ ... }: {
  imports = [
    ./hyprland.nix
    ./boot.nix
    ./timelocale.nix
    ./pipewire.nix
    ./bluetooth.nix
    ./gpg.nix

  ];
}
