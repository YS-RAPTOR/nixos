{
  den.aspects.tooling.direnv.homeManager.programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.global.log_filter = "^$";
  };
}
