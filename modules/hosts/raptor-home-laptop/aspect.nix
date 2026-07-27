{ den, ... }: {
  den.aspects.raptor-home-laptop = {
    includes = [
      den.aspects.system.base.core
      den.aspects.system.locale
      den.aspects.system.boot.efi-grub
      den.aspects.services.networking.networkmanager
      den.aspects.services.audio.pipewire
      den.aspects.services.bluetooth
      den.aspects.services.printing.cups
      den.aspects.desktop.session.login.regreet
      (den.batteries.system.hardware.graphics.nvidia-prime {
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      })
      (den.batteries.system.hardware.brightness.display [
        "intel_backlight"
        "nvidia_0"
      ])
      (den.batteries.system.hardware.brightness.keyboard {
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
