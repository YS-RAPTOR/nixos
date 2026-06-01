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
        default = "openai/gpt-5.5";
        defaultSmall = "openai/gpt-5.4-mini";
    };

    startup = [ ];

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
