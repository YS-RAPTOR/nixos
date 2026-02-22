{
    id = "work";

    system = {
        target = "x86_64-linux";
        hostname = "raptor-work";
        timezone = "Australia/Melbourne";
        locale = "en_AU.UTF-8";
        keyboardLayout = "au";
        unstable = true;
    };

    user = rec {
        username = "yashan";
        github-username = "yashan-sumanaratne";
        name = "Yashan";
        email = "yashan.sumanaratne@oolio.com";

        homeDir = "/home/${username}";
        nixDir = "${homeDir}/NixOS";
        extraDir = "${nixDir}/extras";
        wallpaper = "${extraDir}/Work Wallpaper.jpg";
    };

    packages = import ./packages.nix;

    ai = {
        default = "anthropic/claude-opus-4-6";
        defaultSmall = "anthropic/claude-haiku-4-5";
    };

    wm = {
        dunst.monitorId = 1;
        monitors = [
            {
                name = "eDP-1";
                resolution = "1920x1200";
                refreshRate = "60.00Hz";
                position = "960x0";
                scale = "1";
                workspaces = [
                    1
                    2
                    3
                    4
                    5
                ];
            }
            {
                name = "DP-1";
                resolution = "1920x1080";
                refreshRate = "74.99Hz";
                position = "0x-1080";
                scale = "1";
                workspaces = [
                    6
                    7
                    8
                    9
                    10
                ];
            }
        ];
    };

    hardware = {
        configFile = ./hardware-configuration.nix;
        gpu = {
            type = "intel";
        };
        backlights = [ "intel_backlight" ];
        keyboard = {
            backlight = {
                device = "tpacpi::kbd_backlight";
                maxValue = "2";
            };
        };
    };
}
