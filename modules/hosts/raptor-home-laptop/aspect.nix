{ den, ... }: {
  den.aspects.raptor-home-laptop = {
    includes = [
      den.aspects.system.core
      den.aspects.system.locale
      den.aspects.system.efi-grub
      den.aspects.services.network
      den.aspects.services.pipewire
      den.aspects.services.bluetooth
      den.aspects.services.printing
      den.aspects.shell.login
      (den.batteries.nvidia-prime {
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      })
      (den.batteries.display-brightness [
        "intel_backlight"
        "nvidia_0"
      ])
      (den.batteries.keyboard-brightness {
        device = "platform::kbd_backlight";
        maxValue = 2;
      })
    ];

    nixos = {
      imports = [
        ./_nix/hardware-configuration.nix
        ./_nix/storage.nix
      ];

      time.hardwareClockInLocalTime = true;
      boot.loader.grub.useOSProber = true;
    };
  };
}
