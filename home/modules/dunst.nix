{
    lib,
    config,
    ...
}:
{
    services.dunst = {
        enable = true;
        settings = {
            global = {
                follow = "keyboard";
            };
            urgency_normal = {
                frame_color = lib.mkForce "#${config.lib.stylix.colors.base0B}";
            };
        };
    };

}
