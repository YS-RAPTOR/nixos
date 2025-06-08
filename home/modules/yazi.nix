{ ... }: {
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      manager.show_hidden = true;
      preview = {
        wrap = "yes";
        max_width = 500;
        max_height = 1000;
      };

    };
  };
}
