{
    lib,
    settings,
    config,
    ...
}:
{
    services.dunst = {
        enable = true;
        settings = {
            global = {
                monitor = settings.wm.dunst.monitorId;
            };
            urgency_normal = {
                frame_color = lib.mkForce "#${config.lib.stylix.colors.base0B}";
            };
        };
    };

}
