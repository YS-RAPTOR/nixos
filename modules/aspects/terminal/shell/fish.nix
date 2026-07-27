{
  den.aspects.terminal.shell.fish.homeManager.programs.fish = {
    enable = true;

    shellInit = ''
      set fish_cursor_default block
      set fish_cursor_insert line
      set fish_cursor_replace_one underscore
      set fish_cursor_replace underscore
      set fish_cursor_external line
      set fish_cursor_visual block
      set -g fish_greeting
    '';

    functions = {
      _bind_bang = ''
        switch (commandline -t)
          case "!"
            commandline -t $history[1]
            commandline -f repaint
          case "*"
            commandline -i !
        end
      '';

      _bind_dollar = ''
        switch (commandline -t)
          case "!"
            commandline -t ""
            commandline -f history-token-search-backward
          case "*"
            commandline -i '$'
        end
      '';

      fish_user_key_bindings = ''
        fish_vi_key_bindings
        bind -M insert \cf accept-autosuggestion
        bind -M insert \ef forward-word
        bind -M default \cl nextd-or-forward-word
        bind -M default \ch prevd-or-backward-word
        bind -M insert ! _bind_bang
        bind -M insert '$' _bind_dollar
      '';
    };
  };
}
