{
  den.aspects.desktop.session.polkit.hyprpolkitagent = {
    nixos.security.polkit.enable = true;
    homeManager.services.hyprpolkitagent.enable = true;
  };
}
