{ ... }:
{
    programs.yazi = {
        enable = true;
        enableFishIntegration = true;
        shellWrapperName = "y";
        settings = {
            mgr.show_hidden = true;
            preview = {
                wrap = "yes";
                max_width = 500;
                max_height = 1000;
            };

        };
    };
}
