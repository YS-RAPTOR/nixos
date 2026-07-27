{ den, ... }: {
  den.aspects.desktop.session.idle.brightness = {
    includes = [ den.aspects.desktop.session.idle.hypridle ];
    homeManager.services.hypridle.settings.listener = [
      {
        timeout = 60;
        on-timeout = "display-brightness dim";
        on-resume = "display-brightness restore";
      }
      {
        timeout = 60;
        on-timeout = "keyboard-brightness dim";
        on-resume = "keyboard-brightness restore";
      }
    ];
  };
}
