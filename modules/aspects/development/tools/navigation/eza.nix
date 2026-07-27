{
  den.aspects.development.tools.navigation.eza.homeManager = { lib, pkgs, ... }: {
    programs = {
      eza.enable = true;
      fish.shellAliases = {
        ls = "${lib.getExe pkgs.eza} --icons";
        tree = "${lib.getExe pkgs.eza} --tree --icons";
      };
    };
  };
}
