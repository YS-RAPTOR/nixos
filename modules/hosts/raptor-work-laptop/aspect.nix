{ den, ... }: {
  den.aspects.raptor-work-laptop = {
    includes = [
      den.aspects.system.core
      den.aspects.system.locale
      den.aspects.system.efi-grub
      den.aspects.services.network
      den.aspects.services.pipewire
      den.aspects.services.bluetooth
      den.aspects.services.printing
      den.aspects.shell.login
      (den.batteries.display-brightness [ "intel_backlight" ])
      (den.batteries.keyboard-brightness {
        device = "tpacpi::kbd_backlight";
        maxValue = 2;
      })
    ];

    nixos.imports = [
      ./_nix/hardware-configuration.nix
      ./_nix/intel-npu.nix
    ];
  };
}
