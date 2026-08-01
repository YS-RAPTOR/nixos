{ den, ... }: {
  den.aspects.desktop.session.login.regreet = {
    includes = [ den.aspects.appearance.theme.stylix ];
    nixos = {
      services.accounts-daemon.enable = true;

      services.displayManager.regreet = {
        enable = true;

        settings = {
          skip_selection = true;

          background = {
            path = ./_files/pixel-sakura.webm;
            fit = "Cover";
          };

          appearance.greeting_msg = "Welcome back!";

          widget.clock = {
            format = "%H:%M%n%A, %d %B %Y";
            resolution = "1s";
          };
        };
      };

      stylix.targets.regreet.image.enable = false;
    };
  };
}
