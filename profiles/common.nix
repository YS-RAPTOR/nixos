{
    packages = {
        system =
            { pkgs, pkgs-stable }:
            [
                # Essentials
                pkgs.vscode
                pkgs.neovim
                pkgs.firefox
                pkgs.vivaldi
                pkgs.wofi
                pkgs.ghostty
                pkgs.git
                pkgs.fish
                pkgs.bash
                pkgs.nautilus

                # WM
                pkgs.brightnessctl
                pkgs.playerctl
                pkgs.udiskie
                pkgs.pkg-config
                pkgs.waybar
                pkgs.hyprshot
                pkgs.hyprpaper
                pkgs.hyprpicker
                pkgs.hypridle
                pkgs.hyprlock
                pkgs.dunst
                pkgs.cliphist
                pkgs.libnotify
                pkgs.pulseaudio

                # Programming Languages
                pkgs.gcc
                pkgs.zig
                pkgs.cargo
                pkgs.rustc
                pkgs.rust-analyzer
                pkgs.go
                pkgs.dotnet-sdk
                pkgs.bun
                pkgs.nodejs
                pkgs.uv
                pkgs.python315
                pkgs.openjdk
            ];

        home =
            {
                pkgs,
                pkgs-stable,
                extra,
            }:
            [
                pkgs.yazi
                pkgs.tmux
                pkgs.bat
                pkgs.fzf
                pkgs.ripgrep
                pkgs.eza
                pkgs.fd
                pkgs.unzip
                pkgs.lazygit
                pkgs.zoxide
                pkgs.direnv
                pkgs.oh-my-posh
                pkgs.wget
                pkgs.jq
                pkgs.wl-clipboard
                pkgs.networkmanager_dmenu
                pkgs.btop
                pkgs.pavucontrol
                pkgs.freeoffice
                extra.t3code
                extra.claude-code
                pkgs.codex
                extra.opencode
                pkgs.gh
                pkgs.lsof
                pkgs.trash-cli
                pkgs.mermaid-cli
                pkgs.imagemagick
                pkgs.ghostscript
                pkgs.tectonic-unwrapped
                pkgs.maven
                pkgs.android-studio
                pkgs.android-tools
            ];
    };
}
