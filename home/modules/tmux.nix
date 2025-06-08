{ pkgs, userSettings, ... }: {
  programs.tmux = {
    enable = true;

    # Plugin configuration
    plugins = with pkgs; [
      tmuxPlugins.tmux-sensible
      tmuxPlugins.vim-tmux-navigator
      tmuxPlugins.yank
      tmuxPlugins.resurrect
      tmuxPlugins.continuum
      {
        plugin = tmuxPlugins.tmux-sessionx;
        extraConfig = ''
          set -g @sessionx-zoxide-mode 'on'
          set -g @sessionx-window-mode 'on'
          set -g @sessionx-x-path '$HOME/dev/'
          set -g @sessionx-bind-kill-window "alt-d"
          set -g @sessionx-bind-scroll-up "ctrl-u"
          set -g @sessionx-bind-select-up "ctrl-k"
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
      set -g status-position top
      set -g status-interval 1
      set-option -g exit-empty off

      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi C-q send-keys -X rectangle-toggle
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind-key -T root C-_ run-shell "${userSettings.homeDir}/nixos/tmux/console.sh"

      # Remaps
      unbind C-b
      set -g prefix C-Space
      bind C-Space send-prefix

      unbind '"'
      unbind %
      unbind &

      set -g allow-passthrough on
      set -ga update-environment TERM
      set -ga update-environment TERM_PROGRAM

      bind v copy-mode
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind D kill-window
      bind _ delete-buffer

      # tmux status bar
      set-option -g status-left-length 100
      set-option -g status-right-length 100

      set-option -g window-status-activity-style "italics"
      set-option -g window-status-bell-style "bold"

      # message styling
      set-option -g message-style "bg=#f7768e,fg=#1e2030"
      # status bar
      set-option -g status-style "bg=default,fg=#ffffff"

      # border color
      set-option -g pane-active-border-style "fg=#1abc9c"
      set-option -g pane-border-style "fg=#16161e"

      ### Left side
      set-option -g status-left "#[fg=#3b4261,bold]#{?client_prefix,#[bg=#ff9e64],#[bg=#2abc9c]} #{?client_prefix,󰰴 ,#[dim]󰤂 }#S #[none, bg=#15151d]#{?client_prefix,#[fg=#ff9e64],#[fg=#1abc9c]}#[none]"

      ### Windows list

      set-option -g window-status-separator ""

      set-option -g window-status-current-format "#[bg=#15152d,fg=#f7768e]#[bg=#f7768e,fg=#212121]#I #{?window_zoomed_flag,󰍋,} #W#[fg=#f7768e,bg=#15151d]#[none]"
      set-option -g window-status-format "#[bg=#15151d,fg=#a9b1d6]#[bg=#a9b1d6,fg=#212121]#I #{?window_zoomed_flag,󰛭,} #W#[fg=#a9b1d6,bg=#15151d]#[none]"

      ### Right side
      set-option -g status-right "#(${userSettings.homeDir}/nixos/tmux/youtube-status.sh)#[bg=#15151d, fg=#9d7cd8]#[fg=#15151d, bg=#9d7cd8] %H:%M:%S#[bg=#9d7cd8, fg=#192c2c]#[bg=#15151d, fg=#7aa2f7]#[bg=#7aa2f7, fg=#15151d] %D "
    '';
  };
}
