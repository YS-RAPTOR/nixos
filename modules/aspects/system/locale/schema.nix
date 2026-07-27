{ lib, ... }: {
  den.schema.host.options = {
    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Australia/Melbourne";
      description = "Host time zone.";
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_AU.UTF-8";
      description = "Host default locale.";
    };

    keyboardLayout = lib.mkOption {
      type = lib.types.str;
      default = "au";
      description = "Host keyboard layout.";
    };
  };
}
