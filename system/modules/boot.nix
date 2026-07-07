{ pkgs, ... }:
{
    boot = {
        loader = {
            efi.canTouchEfiVariables = true;
            grub = {
                enable = true;
                configurationLimit = 25;
                devices = [ "nodev" ];
                efiSupport = true;
                useOSProber = true;
                default = "saved";
                extraEntries = "GRUB_SAVEDEFAULT=true";
            };
        };
        kernelPackages = pkgs.linuxPackages;
        supportedFilesystems = [ "ntfs" ];
    };
}
