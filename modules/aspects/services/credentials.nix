{
  den.aspects.services.credentials = {
    nixos = {
      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
      };

      services.gnome.gnome-keyring.enable = true;
    };

    homeManager.services.gnome-keyring = {
      enable = true;
      components = [ "secrets" ];
    };
  };
}
