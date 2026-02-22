{ pkgs, config, ... }:
let
    colors = config.lib.stylix.colors;
    toggle-workspace = pkgs.writeShellScript "toggle" ''
        WINDOW_COUNT=$(tmux list-windows | wc -l)
        CURRENT_WINDOW=$(tmux display-message -p '#I')
        CURRENT_PATH=$(tmux display-message -p '#{pane_current_path}')

        if [ "$WINDOW_COUNT" -lt 2 ]; then
          tmux new-window -c "$CURRENT_PATH"
          exit 0
        fi

        if [ "$CURRENT_WINDOW" -eq 1 ]; then
          tmux select-window -t 2
        else
          tmux select-window -t 1
        fi
    '';

in
{
    programs.tmux = {
        enable = true;

        # Plugin configuration
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


                    set -g @sessionx-bind-scroll-up "ctrl-u"
                    set -g @sessionx-bind-select-up "ctrl-k"

                    set -g @sessionx-bind-configuration-path 'ctrl-s'
                    set -g @sessionx-bind-kill-session "ctrl-x"
                    set -g @sessionx-bind-select-down "ctrl-j"
                '';

            }
        ];
        sensibleOnTop = true;
        mouse = true;
        baseIndex = 1;
        keyMode = "vi";

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
            bind-key -T root C-_ run-shell ${toggle-workspace}


            # Remaps
            unbind C-b
            set -g prefix C-Space
            bind C-Space send-prefix


            set -g allow-passthrough on
            set -ga update-environment TERM
            set -ga update-environment TERM_PROGRAM

            bind v copy-mode
            bind _ delete-buffer

            # message styling
            set-option -g message-style "bg=#${colors.base08},fg=#${colors.base00}"


            # Pane Unbinds
            # Splitting panes
            unbind '"'
            unbind %
            unbind -
            unbind x

            # Navigating between panes
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

            # Swapping panes
            unbind '{'
            unbind '}'

            # Resizing panes
            unbind M-Up
            unbind M-Down
            unbind M-Left
            unbind M-Right
            unbind C-Up
            unbind C-Down
            unbind C-Left
            unbind C-Right

            # Zooming and rotating panes
            unbind z
            unbind space

            # Window Unbinds
            # Creating and killing windows
            unbind &

            # Switching windows
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

            # Selecting windows by index
            unbind M-n
            unbind M-p

            # Swapping and moving windows
            unbind .
            unbind "'"
            unbind f

            # Layout / reorder window commands
            unbind w
            unbind !
            unbind m
            unbind t

            # (Optional) if you also use mouse, disable window switching by click
            unbind -n MouseDown1Status
            unbind -n MouseDown3Status
            unbind -n WheelUpStatus
            unbind -n WheelDownStatus
        '';
    };
}
