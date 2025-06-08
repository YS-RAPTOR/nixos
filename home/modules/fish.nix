{ ... }: {
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      if not set -q TMUX
        exec tmux -u new -A -D -t base
      end
    '';
    loginShellInit = ''
      if uwsm check may-start
          exec uwsm start hyprland.desktop
      end
    '';
    shellInit = ''
      set fish_cursor_default block
      set fish_cursor_insert line
      set fish_cursor_replace_one underscore
      set fish_cursor_replace underscore
      set fish_cursor_external line
      set fish_cursor_visual block
    '';
    shellAliases = {
      ls = "eza --icons";
      tree = "eza --tree --icons";
      cat = "bat --paging=never";
      less = "bat --paging=always";
    };
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
      fish_mode_prompt = ''
        set_color "#0fb1b1"
        echo " ┌"

        switch $fish_bind_mode
          case insert
            set_color --bold #0fb1b1
          case replace_one
            set_color --bold magenta
          case replace
            set_color --bold magenta
          case visual
            set_color --bold blue
          case '*'
            set_color --bold red
        end

        echo "[]"
        set_color normal
      '';
      fish_user_key_bindings = ''
        fish_vi_key_bindings

        # Accepting Autosuggestion - Ctrl + F
        bind -M insert \cf accept-autosuggestion

        # Accepting One Autosuggestion - Alt + F
        bind -M insert \ef forward-word

        # prevd and nextd
        bind -M default \cl nextd-or-forward-word
        bind -M default \ch prevd-or-backward-word
        bind -M insert ! _bind_bang
        bind -M insert '$' _bind_dollar
      '';
    };
  };
}

