{ lib, ... }: {
  den.schema.user.options.git = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Git author name.";
          };
          email = lib.mkOption {
            type = lib.types.str;
            description = "Git author email address.";
          };
        };
      }
    );
    default = null;
    description = "Git identity for this user.";
  };
}
