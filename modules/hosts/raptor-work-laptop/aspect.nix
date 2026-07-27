{ den, ... }: {
  den.aspects.raptor-work-laptop = {
    includes = [
      den.aspects.system.base.core
      den.aspects.system.locale
      den.aspects.system.boot.efi-grub
      den.aspects.services.networking.networkmanager
      den.aspects.services.audio.pipewire
      den.aspects.services.bluetooth
      den.aspects.services.printing.cups
      den.aspects.desktop.session.login.regreet
      (den.batteries.system.hardware.brightness.display [ "intel_backlight" ])
      (den.batteries.system.hardware.brightness.keyboard {
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
