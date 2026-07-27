{ den, ... }: {
  den.batteries.programs.pager.defaults.bat = {
    includes = [ den.aspects.programs.pager.bat ];
    homeManager.home.sessionVariables = {
      PAGER = "bat --paging=always";
      MANPAGER = "bat --paging=always";
    };
  };
}
