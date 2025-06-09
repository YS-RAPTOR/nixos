{ pkgs, systemSettings, userSettings, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./raptor.nix
    ./packages.nix
    ./modules/zzz.nix
  ];

  networking = {
    hostName = systemSettings.hostname;
    networkmanager.enable = true;
  };

  users.users.${userSettings.username} = {
    isNormalUser = true;
    description = userSettings.name;
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.fish;
  };
  # automount
  services.udisks2.enable = true;

  programs.fish.enable = true;
  programs.nix-ld.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.05";
}
