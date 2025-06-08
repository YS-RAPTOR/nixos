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
          exec uwsm start default 
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

  #Theme
  home.sessionVariables = {
    fish_color_autosuggestion = "565f89";
    fish_color_cancel = "x1d";
    fish_color_command = "7dcfff";
    fish_color_comment = "565f89";
    fish_color_cwd = "x1d";
    fish_color_cwd_root = "red";
    fish_color_end = "ff9e64";
    fish_color_error = "f7768e";
    fish_color_escape = "bb9af7";
    fish_color_history_current = "x2dx2dbold";
    fish_color_host = "x1d";
    fish_color_host_remote = "x1d";
    fish_color_keyword = "bb9af7";
    fish_color_normal = "c0caf5";
    fish_color_operator = "9ece6a";
    fish_color_option = "bb9af7";
    fish_color_param = "9d7cd8";
    fish_color_quote = "e0af68";
    fish_color_redirection = "c0caf5";
    fish_color_search_match = "x2dx2dbackgroundx3d283457";
    fish_color_selection = "x2dx2dbackgroundx3d283457";
    fish_color_status = "red";
    fish_color_user = "x1d";
    fish_color_valid_path = "x2dx2dunderline";
    fish_greeting = "";
    fish_key_bindings = "fish_vi_key_bindings";
    fish_pager_color_background = "x1d";
    fish_pager_color_completion = "c0caf5";
    fish_pager_color_description = "565f89";
    fish_pager_color_prefix = "7dcfff";
    fish_pager_color_progress = "565f89";
    fish_pager_color_secondary_background = "x1d";
    fish_pager_color_secondary_completion = "x1d";
    fish_pager_color_secondary_description = "x1d";
    fish_pager_color_secondary_prefix = "x1d";
    fish_pager_color_selected_background = "x2dx2dbackgroundx3d283457";
    fish_pager_color_selected_completion = "x1d";
    fish_pager_color_selected_description = "x1d";
    fish_pager_color_selected_prefix = "x1d";
  };
}

