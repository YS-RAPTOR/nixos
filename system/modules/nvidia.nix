{
    config,
    lib,
    settings,
    ...
}:
let
    isNvidia = settings.hardware.gpu.type == "nvidia";
    nvidia = settings.hardware.gpu.nvidia or { };
in
lib.mkIf isNvidia {
    hardware.graphics = {
        enable = true;
    };
    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        # powerManagement.finegrained = true;
        open = true;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;

        prime = lib.mkIf (nvidia.prime or false) {
            intelBusId = nvidia.intelBusId;
            nvidiaBusId = nvidia.nvidiaBusId;
            offload = {
                enable = true;
                enableOffloadCmd = true;
            };
        };
    };
}
