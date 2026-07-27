{
  den.aspects.services.credentials.gnome-keyring = {
    nixos.services.gnome.gnome-keyring.enable = true;
    homeManager.services.gnome-keyring = {
      enable = true;
      components = [ "secrets" ];
    };
  };
}
