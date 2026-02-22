{ settings, ... }:
{
    programs.ghostty = {
        enable = true;
        settings = {
            app-notifications = "no-clipboard-copy";
            confirm-close-surface = false;
            custom-shader = "${settings.user.extraDir}/shaders/smear.glsl";
        };
    };
}
