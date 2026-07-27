{ den, ... }: {
  den.aspects.services.bluetooth.includes = [
    den.aspects.services.bluetooth.blueman
    den.aspects.services.bluetooth.bluez
  ];
}
