{
  den.aspects.services.storage.removable-media = {
    nixos.services.udisks2.enable = true;
    homeManager.services.udiskie.enable = true;
  };
}
