{ den, ... }: {
  den.batteries.terminal.defaults = {
    ghostty = {
      includes = [ den.aspects.terminal.ghostty ];
      homeManager =
        { lib, pkgs, ... }:
        let
          execute = pkgs.writeShellApplication {
            name = "default-terminal-exec";
            text = ''
              exec ghostty -e "$@"
            '';
          };
        in
        {
          home.sessionVariables.TERMINAL = "ghostty";
          desktop.commands = {
            terminalExec = lib.getExe execute;
            terminalWindowTitle = "Ghostty";
          };
        };
    };

    kitty = {
      includes = [ den.aspects.terminal.kitty ];
      homeManager =
        { lib, pkgs, ... }:
        let
          execute = pkgs.writeShellApplication {
            name = "default-terminal-exec";
            text = ''
              exec kitty "$@"
            '';
          };
        in
        {
          home.sessionVariables.TERMINAL = "kitty";
          desktop.commands = {
            terminalExec = lib.getExe execute;
            terminalWindowTitle = "kitty";
          };
        };
    };
  };
}
