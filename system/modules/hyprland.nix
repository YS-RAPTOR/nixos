{ pkgs, ... }:
{
    programs.hyprland = {
        enable = true;
        withUWSM = true;
        xwayland.enable = true;
    };

    xdg.portal = {
        enable = true;
        extraPortals = [
            pkgs.xdg-desktop-portal-hyprland
            pkgs.xdg-desktop-portal-gtk
        ];
    };

    systemd.user.services.xdg-desktop-portal.unitConfig.ConditionEnvironment =
        "WAYLAND_DISPLAY";

    environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
