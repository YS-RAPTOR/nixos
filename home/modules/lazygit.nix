{ ... }: {
  programs.lazygit = {
    enable = true;
    # dummy setting so that the ml file will be generated
    settings = { gui.language = "en"; };
  };
}
