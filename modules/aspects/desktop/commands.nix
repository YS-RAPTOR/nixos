{ lib, ... }: {
  den.default.homeManager.options.desktop.commands = {
    browser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    privateBrowser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    fileManager = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    launcher = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    terminalExec = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    terminalSession = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    terminalWindowTitle = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };
}
