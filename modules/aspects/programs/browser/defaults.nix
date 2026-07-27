{ den, ... }: {
  den.batteries.programs.browser.defaults = {
    firefox = {
      includes = [ den.aspects.programs.browser.firefox ];
      homeManager = {
        home.sessionVariables.BROWSER = "firefox";
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            "text/html" = "firefox.desktop";
            "x-scheme-handler/http" = "firefox.desktop";
            "x-scheme-handler/https" = "firefox.desktop";
            "x-scheme-handler/about" = "firefox.desktop";
            "x-scheme-handler/unknown" = "firefox.desktop";
          };
        };
        desktop.commands = {
          browser = "firefox";
          privateBrowser = "firefox --private-window";
        };
      };
    };

    vivaldi = {
      includes = [ den.aspects.programs.browser.vivaldi ];
      homeManager = {
        home.sessionVariables.BROWSER = "vivaldi";
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            "text/html" = "vivaldi-stable.desktop";
            "x-scheme-handler/http" = "vivaldi-stable.desktop";
            "x-scheme-handler/https" = "vivaldi-stable.desktop";
            "x-scheme-handler/about" = "vivaldi-stable.desktop";
            "x-scheme-handler/unknown" = "vivaldi-stable.desktop";
          };
        };
        desktop.commands = {
          browser = "vivaldi";
          privateBrowser = "vivaldi -incognito";
        };
      };
    };
  };
}
