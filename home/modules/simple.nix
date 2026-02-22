{ ... }:
{
    programs = {
        bat.enable = true;
        lazygit.enable = true;
        btop.enable = true;
        vscode.enable = true;
        wofi.enable = true;
        bash.enable = true;

    };

    services = {
        udiskie.enable = true;
        hyprpolkitagent.enable = true;
        cliphist.enable = true;
        gnome-keyring = {
            enable = true;
            components = [ "secrets" ];
        };

    };

}
