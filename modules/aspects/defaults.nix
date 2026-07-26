{
  den.batteries = {
    editor.default = { command }: {
      homeManager = { lib, ... }: {
        home.sessionVariables = {
          EDITOR = lib.escapeShellArgs command;
          VISUAL = lib.escapeShellArgs command;
        };
      };
    };

    pager.default = { command }: {
      homeManager = { lib, ... }: {
        home.sessionVariables = {
          PAGER = lib.escapeShellArgs command;
          MANPAGER = lib.escapeShellArgs command;
        };
      };
    };

    terminal.default =
      {
        command,
        execArgs,
        windowTitle,
      }:
      {
        homeManager =
          { lib, pkgs, ... }:
          let
            execute = pkgs.writeShellApplication {
              name = "default-terminal-exec";
              text = ''
                exec ${lib.escapeShellArgs (command ++ execArgs)} "$@"
              '';
            };
          in
          {
            home.sessionVariables = {
              TERMINAL = lib.escapeShellArgs command;
              TERMINAL_EXEC = lib.getExe execute;
              TERMINAL_WINDOW_TITLE = windowTitle;
            };
          };
      };

    browser.default =
      {
        command,
        privateCommand,
        desktopFile,
      }:
      {
        homeManager = { lib, ... }: {
          home.sessionVariables = {
            BROWSER = lib.escapeShellArgs command;
            DEFAULT_BROWSER = lib.escapeShellArgs command;
            PRIVATE_BROWSER = lib.escapeShellArgs privateCommand;
          };
          xdg.mimeApps = {
            enable = true;
            defaultApplications = {
              "text/html" = desktopFile;
              "x-scheme-handler/http" = desktopFile;
              "x-scheme-handler/https" = desktopFile;
              "x-scheme-handler/about" = desktopFile;
              "x-scheme-handler/unknown" = desktopFile;
            };
          };
        };
      };

    file-manager.default = { command }: {
      homeManager = { lib, ... }: { home.sessionVariables.FILE_MANAGER = lib.escapeShellArgs command; };
    };

    launcher.default = { command }: {
      homeManager = { lib, ... }: { home.sessionVariables.APP_LAUNCHER = lib.escapeShellArgs command; };
    };
  };
}
