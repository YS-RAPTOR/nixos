{
  den.aspects.shell.polkit = {
    nixos.security.polkit.enable = true;
    homeManager.services.hyprpolkitagent.enable = true;
  };
}
