{
    pkgs,
    config,
    settings,
    ...
}:
let
    theme = pkgs.sddm-astronaut.override {
        embeddedTheme = "hyprland_kath";
        themeConfig = {
            DateFormat = "ddd d MMMM yyyy";

            Font = config.stylix.fonts.monospace.name;

            HeaderTextColor = "#${config.lib.stylix.colors.base05}";
            DateTextColor = "#${config.lib.stylix.colors.base05}";
            TimeTextColor = "#${config.lib.stylix.colors.base05}";

            FormBackgroundColor = "#${config.lib.stylix.colors.base00}";
            BackgroundColor = "#${config.lib.stylix.colors.base00}";
            DimBackgroundColor = "#${config.lib.stylix.colors.base00}";

            LoginFieldBackgroundColor = "#${config.lib.stylix.colors.base01}";
            PasswordFieldBackgroundColor = "#${config.lib.stylix.colors.base01}";
            LoginFieldTextColor = "#${config.lib.stylix.colors.base05}";
            PasswordFieldTextColor = "#${config.lib.stylix.colors.base05}";
            UserIconColor = "#${config.lib.stylix.colors.base05}";
            PasswordIconColor = "#${config.lib.stylix.colors.base05}";

            PlaceholderTextColor = "#${config.lib.stylix.colors.base03}";
            WarningColor = "#${config.lib.stylix.colors.base08}";

            LoginButtonTextColor = "#${config.lib.stylix.colors.base06}";
            LoginButtonBackgroundColor = "#${config.lib.stylix.colors.base0B}";
            SystemButtonsIconsColor = "#${config.lib.stylix.colors.base0C}";
            SessionButtonTextColor = "#${config.lib.stylix.colors.base0C}";
            VirtualKeyboardButtonTextColor = "#${config.lib.stylix.colors.base0C}";

            DropdownTextColor = "#${config.lib.stylix.colors.base06}";
            DropdownSelectedBackgroundColor = "#${config.lib.stylix.colors.base0B}";
            DropdownBackgroundColor = "#${config.lib.stylix.colors.base00}";

            HighlightTextColor = "#${config.lib.stylix.colors.base06}";
            HighlightBackgroundColor = "#${config.lib.stylix.colors.base0B}";
            HighlightBorderColor = "#${config.lib.stylix.colors.base0B}";

            HoverUserIconColor = "#${config.lib.stylix.colors.base0B}";
            HoverPasswordIconColor = "#${config.lib.stylix.colors.base0B}";
            HoverSystemButtonsIconsColor = "#${config.lib.stylix.colors.base0B}";
            HoverSessionButtonTextColor = "#${config.lib.stylix.colors.base0B}";
            HoverVirtualKeyboardButtonTextColor = "#${config.lib.stylix.colors.base0B}";

            HideSystemButtons = false;
            BlurMax = 48;
            AllowEmptyPassword = true;
        };
    };
in
{
    services = {
        displayManager = {
            sddm = {
                enable = true;
                wayland.enable = true;
                theme = "sddm-astronaut-theme";
                autoNumlock = true;
                autoLogin.relogin = true;
            };
            autoLogin = {
                enable = false;
                user = settings.user.username;
            };
        };
    };

    environment.systemPackages = [
        theme
        pkgs.kdePackages.qtsvg
        pkgs.kdePackages.qtvirtualkeyboard
        pkgs.kdePackages.qtmultimedia
    ];
}
