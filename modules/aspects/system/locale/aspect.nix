{
  den.aspects.system.locale = { host, ... }: {
    nixos = {
      time.timeZone = host.timezone;

      i18n = {
        defaultLocale = host.locale;
        extraLocaleSettings = {
          LC_ADDRESS = host.locale;
          LC_IDENTIFICATION = host.locale;
          LC_MEASUREMENT = host.locale;
          LC_MONETARY = host.locale;
          LC_NAME = host.locale;
          LC_NUMERIC = host.locale;
          LC_PAPER = host.locale;
          LC_TELEPHONE = host.locale;
          LC_TIME = host.locale;
        };
      };

      services.xserver.xkb.layout = host.keyboardLayout;
      console.useXkbConfig = true;
    };
  };
}
