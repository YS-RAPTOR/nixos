{ den, ... }: {
  den.batteries.terminal.defaults = {
    ghostty = {
      includes = [ den.aspects.terminal.ghostty ];
      homeManager.home.sessionVariables.TERMINAL = "ghostty";
    };

    kitty = {
      includes = [ den.aspects.terminal.kitty ];
      homeManager.home.sessionVariables.TERMINAL = "kitty";
    };
  };
}
