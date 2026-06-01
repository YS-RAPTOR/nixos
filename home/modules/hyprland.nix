{
    config,
    pkgs,
    settings,
    ...
}:
{
    xdg.configFile."hypr/hyprland.lua".source =
        config.lib.file.mkOutOfStoreSymlink "${settings.user.extraDir}/hypr/hyprland.lua";

    xdg.configFile."hypr/lua".source =
        config.lib.file.mkOutOfStoreSymlink "${settings.user.extraDir}/hypr/lua";

    xdg.configFile."hypr/stubs".source = "${pkgs.hyprland}/share/hypr/stubs";
}
