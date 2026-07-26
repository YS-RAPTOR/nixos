{ lib, ... }:
let
  commandType = lib.types.addCheck (lib.types.listOf lib.types.str) (command: command != [ ]);
in
{
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

  den.schema.user.options = {
    user = lib.mkOption {
      type = lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "User display and Git author name.";
          };

          email = lib.mkOption {
            type = lib.types.str;
            description = "User Git author email address.";
          };
        };
      };
    };

    git = lib.mkOption {
      type = lib.types.submodule {
        options.username = lib.mkOption {
          type = lib.types.str;
          description = "GitHub account username.";
        };
      };
    };

    wallpaper = lib.mkOption {
      type = lib.types.path;
      description = "User desktop wallpaper.";
    };

    startup = lib.mkOption {
      default = [ ];
      description = "Applications started with the graphical session.";
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            argv = lib.mkOption {
              type = commandType;
              description = "Executable and arguments used to start the application.";
            };

            workspaceByMonitorCount = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              description = "Target workspace selected by connected monitor count.";
            };
          };
        }
      );
    };
  };
}
