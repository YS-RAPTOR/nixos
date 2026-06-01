{
    extra,
    pkgs,
    pkgs-stable,
    settings,
    ...
}:
{
    imports = [
        settings.hardware.configFile
        ./modules/zzz.nix
    ];

    # Windows stuff
    time.hardwareClockInLocalTime = true;

    # Simple networking setup
    networking = {
        hostName = settings.system.hostname;
        networkmanager.enable = true;
    };

    # Simple one-liners
    services = {
        printing.enable = true;
        libinput.enable = true;
    };

    virtualisation.docker = {
        enable = true;
    };

    # User setup
    users.users.${settings.user.username} = {
        isNormalUser = true;
        description = settings.user.name;
        extraGroups = [
            "networkmanager"
            "wheel"
            "docker"
        ];
        shell = pkgs.fish;
        packages = settings.packages.home {
            pkgs = pkgs;
            pkgs-stable = pkgs-stable;
            extra = extra;
        };
    };

    # System package setup
    environment.systemPackages = settings.packages.system {
        pkgs = pkgs;
        pkgs-stable = pkgs-stable;
    };

    # Gnome keyring for secret storage (auto-unlocked via PAM on login)
    services.gnome.gnome-keyring.enable = true;

    # Simple programs and services that are required
    services.udisks2.enable = true;
    programs.fish.enable = true;
    programs.nix-ld.enable = true;
    services.gvfs.enable = true;
    services.envfs.enable = true;

    # NixOS settings
    nix.settings.experimental-features = [
        "nix-command"
        "flakes"
    ];
    system.stateVersion = "26.05";
}
