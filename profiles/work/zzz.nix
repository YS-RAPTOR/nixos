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
                (launchToWorkspace "CONTROL1" "vivaldi-stable" "vivaldi")
                (launchToWorkspace "CONTROL2" "vivaldi-oolio.atlassian"
                    "vivaldi --app=https://oolio.atlassian.net/jira/software/c/projects/GREEN/boards/1126"
                )
                (launchToWorkspace "CONTROL3" "vivaldi-outlook" "vivaldi --app=https://outlook.office.com/mail/0/")
                "[workspace name:CONTROL4 silent] slack"
                "[workspace name:CONTROL5 silent] teams-for-linux"
            ];
        dunst.monitorId = 2;
        workspaces = [
            {
                name = "1";
                key = "1";
            }
            {
                name = "2";
                key = "2";
            }
            {
                name = "3";
                key = "3";
            }
            {
                name = "4";
                key = "4";
            }
            {
                name = "5";
                key = "5";
            }
        ];
        monitors = [
            {
                # Laptop monitor
                name = "eDP-1";
                resolution = "1920x1200";
                refreshRate = "60.00Hz";
                position = "960x0";
                scale = "1";
                workspaceModifier = "";
            }
            {
                # Left Monitor
                name = "DP-5";
                resolution = "1920x1080";
                refreshRate = "74.99Hz";
                position = "0x-1080";
                scale = "1";
                workspaceModifier = "CONTROL";
            }
            {
                # Right Monitor
                name = "DP-3";
                resolution = "1920x1080";
                refreshRate = "74.99Hz";
                position = "1920x-1080";
                scale = "1";
                workspaceModifier = "ALT";
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
