{ ... }: {
  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "CaskaydiaCove Nerd Font Mono";
      theme = "tokyonight_night";
      app-notifications = "no-clipboard-copy";
      background = "#000000";
      background-opacity = 0.1;
      font-size = 10;
      confirm-close-surface = false;
    };

  };
}
