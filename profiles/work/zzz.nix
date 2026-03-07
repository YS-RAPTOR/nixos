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
        startup =
            pkgs:
            let
                launchToWorkspace = import ../../lib/launch-to-workspace.nix { inherit pkgs; };
            in
            [
                (launchToWorkspace "C-1" "vivaldi-stable" "vivaldi")
                "[workspace name:C-2 silent] slack"
                "[workspace name:C-3 silent] teams-for-linux"
            ];
        dunst.monitorId = 2;
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
            {
                name = "C-1";
                key = "1";
                keyModifier = "CONTROL";
                monitor = "DP-5";
                rule = "name:C-1, monitor:DP-5, default:true";
            }
            {
                name = "C-2";
                key = "2";
                keyModifier = "CONTROL";
                monitor = "DP-5";
                rule = "name:C-2, monitor:DP-5, default:true";
            }
            {
                name = "C-3";
                key = "3";
                keyModifier = "CONTROL";
                monitor = "DP-5";
                rule = "name:C-3, monitor:DP-5, default:true";
            }
            {
                name = "C-4";
                key = "4";
                keyModifier = "CONTROL";
                monitor = "DP-5";
                rule = "name:C-4, monitor:DP-5, default:true";
            }
            {
                name = "C-5";
                key = "5";
                keyModifier = "CONTROL";
                monitor = "DP-5";
                rule = "name:C-5, monitor:DP-5, default:true";
            }
            {
                name = "A-1";
                key = "1";
                keyModifier = "ALT";
                monitor = "HDMI-A-1";
                rule = "name:A-1, monitor:HDMI-A-1, default:true";
            }
            {
                name = "A-2";
                key = "2";
                keyModifier = "ALT";
                monitor = "HDMI-A-1";
                rule = "name:A-2, monitor:HDMI-A-1, default:true";
            }
            {
                name = "A-3";
                key = "3";
                keyModifier = "ALT";
                monitor = "HDMI-A-1";
                rule = "name:A-3, monitor:HDMI-A-1, default:true";
            }
            {
                name = "A-4";
                key = "4";
                keyModifier = "ALT";
                monitor = "HDMI-A-1";
                rule = "name:A-4, monitor:HDMI-A-1, default:true";
            }
            {
                name = "A-5";
                key = "5";
                keyModifier = "ALT";
                monitor = "HDMI-A-1";
                rule = "name:A-5, monitor:HDMI-A-1, default:true";
            }
        ];
        monitors = [
            # Laptop monitor
            "eDP-1,1920x1200@60.00Hz,960x0,1"
            # Left monitor
            "DP-5,1920x1080@74.99Hz,0x-1080,1"
            # Right monitor
            "HDMI-A-1,1920x1080@74.99Hz,1920x-1080,1"
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
