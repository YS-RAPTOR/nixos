{
    id = "home";

    system = {
        target = "x86_64-linux";
        hostname = "raptor-laptop";
        timezone = "Australia/Melbourne";
        locale = "en_AU.UTF-8";
        keyboardLayout = "au";
        unstable = true;
    };

    user = rec {
        username = "raptor";
        github-username = "YS-RAPTOR";
        name = "Yashan";
        email = "yashan.sumanaratne@gmail.com";

        homeDir = "/home/${username}";
        nixDir = "${homeDir}/NixOS";
        extraDir = "${nixDir}/extras";
        wallpaper = "${extraDir}/Home Wallpaper.png";
    };

    packages = import ./packages.nix;

    ai = {
        default = "openai/gpt-5.4";
        defaultSmall = "openai/gpt-5.4";
    };

    wm = {
        startup = pkgs: [ ];
        dunst.monitorId = 0;
        workspaces = [
            {
                name = "N-1";
                key = "1";
                keyModifier = "";
                monitor = "eDP-1";
                rule = "name:N-1, monitor:eDP-1, default:true, layout:scrolling";
            }
            {
                name = "N-2";
                key = "2";
                keyModifier = "";
                monitor = "eDP-1";
                rule = "name:N-2, monitor:eDP-1, default:true, layout:scrolling";
            }
            {
                name = "N-3";
                key = "3";
                keyModifier = "";
                monitor = "eDP-1";
                rule = "name:N-3, monitor:eDP-1, default:true, layout:scrolling";
            }
            {
                name = "N-4";
                key = "4";
                keyModifier = "";
                monitor = "eDP-1";
                rule = "name:N-4, monitor:eDP-1, default:true";
            }
            {
                name = "N-5";
                key = "5";
                keyModifier = "";
                monitor = "eDP-1";
                rule = "name:N-5, monitor:eDP-1, default:true";
            }
        ];
        monitors = [
            "eDP-1,3200x2000@120.00Hz,auto,1.6"
        ];
    };

    hardware = {
        configFile = ./hardware-configuration.nix;
        gpu = {
            type = "nvidia";
            nvidia = {
                prime = true;
                intelBusId = "PCI:0:2:0";
                nvidiaBusId = "PCI:1:0:0";
            };
        };
        backlights = [
            "intel_backlight"
            "nvidia_0"
        ];
        keyboard = {
            backlight = {
                device = "platform::kbd_backlight";
                maxValue = "2";
            };
        };
    };
}
