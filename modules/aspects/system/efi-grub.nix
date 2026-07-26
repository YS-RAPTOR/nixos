{
  den.aspects.system.efi-grub.nixos.boot.loader = {
    efi.canTouchEfiVariables = true;

    grub = {
      enable = true;
      configurationLimit = 25;
      devices = [ "nodev" ];
      efiSupport = true;
      default = "saved";
    };
  };
}
