{ den, ... }: {
  den.aspects.terminal.tmux = {
    includes = [ den.aspects.shell.stylix ];
    homeManager =
      { config, pkgs, ... }:
      let
        colors = config.lib.stylix.colors;
        toggleWorkspace = pkgs.writeShellApplication {
          name = "tmux-toggle-workspace";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.tmux
          ];
          text = ''
            window_count=$(tmux list-windows | wc -l)
            current_window=$(tmux display-message -p '#I')
            current_path=$(tmux display-message -p '#{pane_current_path}')

            if [ "$window_count" -lt 2 ]; then
                tmux new-window -c "$current_path"
            elif [ "$current_window" -eq 1 ]; then
                tmux select-window -t 2
            else
                tmux select-window -t 1
            fi
          '';
        };
      in
      {
        home.packages = [
          pkgs.fzf
          pkgs.wl-clipboard
          pkgs.zoxide
        ];

        programs.tmux = {
          enable = true;
          sensibleOnTop = true;
          mouse = true;
          baseIndex = 1;
          keyMode = "vi";

          plugins = with pkgs.tmuxPlugins; [
            sensible
            yank
            resurrect
            continuum
            {
              plugin = tmux-sessionx;
              extraConfig = ''
                set -g @sessionx-bind 'c'
                set -g @sessionx-x-path '$HOME/Dev/'
                set -g @sessionx-zoxide-mode 'on'
                set -g @sessionx-window-mode 'on'
                set -g @sessionx-tree-mode 'off'
                set -g @sessionx-bind-scroll-up 'ctrl-u'
                set -g @sessionx-bind-select-up 'ctrl-k'
                set -g @sessionx-bind-configuration-path 'ctrl-s'
                set -g @sessionx-bind-kill-session 'ctrl-x'
                set -g @sessionx-bind-select-down 'ctrl-j'
              '';
            }
          ];

          extraConfig = ''
            set -ag terminal-overrides ",xterm-256color:RGB"
            set-option -g renumber-windows on
            set -g status off
            set-option -g exit-empty on
            set -s extended-keys on
            set -as terminal-features 'xterm*:extkeys'

            bind-key -T copy-mode-vi v send-keys -X begin-selection
            bind-key -T copy-mode-vi C-q send-keys -X rectangle-toggle
            bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
            bind-key -T root C-_ run-shell ${toggleWorkspace}/bin/tmux-toggle-workspace

            unbind C-b
            set -g prefix C-Space
            bind C-Space send-prefix

            set -g allow-passthrough on
            set -ga update-environment TERM
            set -ga update-environment TERM_PROGRAM

            bind v copy-mode
            bind _ delete-buffer

            set-option -g message-style "bg=#${colors.base08},fg=#${colors.base00}"

            unbind '"'
            unbind %
            unbind -
            unbind x
            unbind Up
            unbind Down
            unbind Left
            unbind Right
            unbind h
            unbind j
            unbind k
            unbind l
            unbind o
            unbind ';'
            unbind '{'
            unbind '}'
            unbind M-Up
            unbind M-Down
            unbind M-Left
            unbind M-Right
            unbind C-Up
            unbind C-Down
            unbind C-Left
            unbind C-Right
            unbind z
            unbind space
            unbind &
            unbind n
            unbind p
            unbind l
            unbind 0
            unbind 1
            unbind 2
            unbind 3
            unbind 4
            unbind 5
            unbind 6
            unbind 7
            unbind 8
            unbind 9
            unbind M-n
            unbind M-p
            unbind .
            unbind "'"
            unbind f
            unbind w
            unbind !
            unbind m
            unbind t
            unbind -n MouseDown1Status
            unbind -n MouseDown3Status
            unbind -n WheelUpStatus
            unbind -n WheelDownStatus
          '';
        };
      };
  };
}
