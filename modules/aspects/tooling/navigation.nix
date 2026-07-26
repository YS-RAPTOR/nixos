{
  den.aspects.tooling.navigation.homeManager = { lib, pkgs, ... }: {
    programs = {
      eza.enable = true;
      fish.shellAliases = {
        ls = "${lib.getExe pkgs.eza} --icons";
        tree = "${lib.getExe pkgs.eza} --tree --icons";
      };
      fzf = {
        enable = true;
        enableFishIntegration = true;
      };
      zoxide = {
        enable = true;
        enableFishIntegration = true;
        options = [ "--cmd cd" ];
      };
    };
  };
}
