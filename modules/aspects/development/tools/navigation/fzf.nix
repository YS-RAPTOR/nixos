{
  den.aspects.development.tools.navigation.fzf.homeManager = { pkgs, ... }: {
    programs = {
      fish.plugins = [
        {
          name = "fzf-fish";
          src = pkgs.fishPlugins.fzf-fish.src;
        }
      ];
      fzf = {
        enable = true;
        enableFishIntegration = true;
      };
    };
  };
}
