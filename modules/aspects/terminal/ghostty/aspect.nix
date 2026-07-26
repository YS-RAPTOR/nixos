{
  den.aspects.terminal.ghostty.homeManager.programs.ghostty = {
    enable = true;
    settings = {
      app-notifications = "no-clipboard-copy";
      confirm-close-surface = false;
      custom-shader = toString ./_files/smear.glsl;
    };
  };
}
