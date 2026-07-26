{
  den.aspects.tooling.pager.homeManager = { lib, pkgs, ... }: {
    programs = {
      bat.enable = true;
      fish.shellAliases = {
        cat = "${lib.getExe pkgs.bat} --paging=never";
        less = "${lib.getExe pkgs.bat} --paging=always";
      };
    };
  };
}
