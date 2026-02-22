{
    config,
    pkgs,
    pkgs-stable,
    settings,
    ...
}:

{
    imports = [ ./modules/zzz.nix ];

    # User setup
    home.username = settings.user.username;
    home.homeDirectory = settings.user.homeDir;

    # NeoVim setup
    xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${settings.user.extraDir}/nvim";
    # xdg.configFile."opencode".source =
    #   config.lib.file.mkOutOfStoreSymlink "${settings.user.extraDir}/opencode";
    xdg.configFile."dictionary".source =
        config.lib.file.mkOutOfStoreSymlink "${settings.user.extraDir}/dictionary";

    # Environment Variables
    home.sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
        PAGER = "bat --paging=always";
        MANPAGER = "bat --paging=always";
        BROWSER = "vivaldi";
        DEFAULT_BROWSER = "vivaldi";
        XDG_DESKTOP_DIR = "$HOME/Desktop";
        XDG_DOWNLOAD_DIR = "$HOME/Downloads";
        XDG_DOCUMENTS_DIR = "$HOME/Documents";
        XDG_MUSIC_DIR = "$HOME/Music";
        XDG_PICTURES_DIR = "$HOME/Pictures";
        XDG_VIDEOS_DIR = "$HOME/Videos";
        XDG_PUBLICSHARE_DIR = "$HOME/Public";
    };

    xdg = {
        mimeApps = {
            enable = true;
            defaultApplications = {
                "text/html" = "vivaldi-stable.desktop";
                "x-scheme-handler/http" = "vivaldi-stable.desktop";
                "x-scheme-handler/https" = "vivaldi-stable.desktop";
                "x-scheme-handler/about" = "vivaldi-stable.desktop";
                "x-scheme-handler/unknown" = "vivaldi-stable.desktop";
                "x-scheme-handler/discord" = "vesktop.desktop";
            };
        };
        portal.config.common.default = "*";
    };

    stylix.targets.waybar.enable = false;
    home.stateVersion = "25.05";
}
