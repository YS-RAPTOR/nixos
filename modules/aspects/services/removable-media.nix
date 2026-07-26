{
  den.aspects.services.removable-media = {
    nixos.services.udisks2.enable = true;
    homeManager.services.udiskie.enable = true;
  };
}
