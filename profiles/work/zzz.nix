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
        default = "openai/gpt-5.5";
        defaultSmall = "openai/gpt-5.4-mini";
    };

    startup = [
        {
            command = "vivaldi";
            workspaceByMonitorCount = {
                "1" = "N-3";
                "2" = "A-1";
                "3" = "C-1";
            };
        }
        {
            command = "slack";
            workspaceByMonitorCount = {
                "1" = "N-3";
                "2" = "A-2";
                "3" = "C-2";
            };
        }
        {
            command = "teams-for-linux";
            workspaceByMonitorCount = {
                "1" = "N-3";
                "2" = "A-3";
                "3" = "C-3";
            };
        }
    ];

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
