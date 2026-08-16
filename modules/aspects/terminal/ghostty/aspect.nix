{ inputs, ... }: {
  den.aspects.terminal.ghostty.homeManager = { pkgs, ... }: {
    programs.ghostty = {
      enable = true;
      package = inputs.stratty.packages.${pkgs.stdenv.hostPlatform.system}.default;
      settings = {
        app-notifications = "no-clipboard-copy";
        background-blur = true;
        bell-audio-path = toString ./_files/herdr-agent-done.mp3;
        bell-features = "system,audio";
        confirm-close-surface = false;
        copy-on-select = "clipboard";
        custom-shader = toString ./_files/smear.glsl;
        keybind = [
          # Disable replaced defaults.
          "ctrl+alt+,=unbind"
          "ctrl+shift+,=unbind"
          "ctrl+shift+enter=unbind"
          "ctrl+shift+f=unbind"
          "ctrl+shift+p=unbind"
          "shift+end=unbind"
          "shift+home=unbind"
          "shift+page_down=unbind"
          "shift+page_up=unbind"

          # Ctrl+Space prefix and literal passthrough.
          "ctrl+space>ctrl+space=text:\\x00"

          # Tab management.
          "ctrl+space>n=new_tab"
          "ctrl+space>x=close_tab:this"
          "ctrl+space>j=next_tab"
          "ctrl+space>k=previous_tab"
          "ctrl+space>shift+j=move_tab:1"
          "ctrl+space>shift+k=move_tab:-1"
          "ctrl+space>1=goto_tab:1"
          "ctrl+space>2=goto_tab:2"
          "ctrl+space>3=goto_tab:3"
          "ctrl+space>4=goto_tab:4"
          "ctrl+space>5=goto_tab:5"
          "ctrl+space>6=goto_tab:6"
          "ctrl+space>7=goto_tab:7"
          "ctrl+space>8=goto_tab:8"
          "ctrl+space>9=last_tab"

          # Vim-style scrollback and search.
          "ctrl+space>ctrl+u=scroll_page_fractional:-0.5"
          "ctrl+space>ctrl+d=scroll_page_fractional:0.5"
          "ctrl+space>g>g=scroll_to_top"
          "ctrl+space>shift+g=scroll_to_bottom"
          "ctrl+space>/=start_search"
          "ctrl+space>shift+e=write_scrollback_file:open"

          # Adjust an existing selection with Vim motions.
          "ctrl+space>v=start_selection"
          "chain=activate_key_table:select"
          "select/h=adjust_selection:left"
          "select/j=adjust_selection:down"
          "select/k=adjust_selection:up"
          "select/l=adjust_selection:right"
          "select/o=toggle_selection_endpoint"
          "select/shift+minus=adjust_selection:beginning_of_line"
          "select/shift+digit_4=adjust_selection:end_of_line"
          "select/ctrl+u=adjust_selection:page_up"
          "select/ctrl+d=adjust_selection:page_down"
          "select/g>g=scroll_to_top"
          "chain=adjust_selection:home"
          "select/shift+g=scroll_to_bottom"
          "chain=adjust_selection:end"
          "select/y=copy_to_clipboard:mixed"
          "chain=deactivate_key_table"
          "select/escape=deactivate_key_table"
          "select/q=deactivate_key_table"
        ];
        selection-clear-on-copy = true;
        scrollback-limit-bytes = 1000000000;
        scrollbar = "never";
        scroll-to-bottom = "no-keystroke,no-output";
        window-padding-color = "extend";
        notify-on-command-finish = "unfocused";
        notify-on-command-finish-action = "bell,no-notify";
        notify-on-command-finish-after = "100ms";
      };
    };
  };
}
