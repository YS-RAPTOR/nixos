{ lib, ... }: {
  den.schema.user.options.wallpaper = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "User desktop wallpaper.";
  };
}
