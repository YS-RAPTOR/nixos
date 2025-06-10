{ ... }: {
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config = {
      global = { log_filter = "^$"; };

    };
  };
}
