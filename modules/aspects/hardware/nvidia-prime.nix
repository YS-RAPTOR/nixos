{
  den.batteries.nvidia-prime = { intelBusId, nvidiaBusId }: {
    description = "Configures NVIDIA PRIME render offload.";

    includes = [
      ({ host, ... }: {
        name = "nvidia-prime@${host.name}";
        nixos = { config, ... }: {
          hardware = {
            graphics.enable = true;
            nvidia = {
              modesetting.enable = true;
              powerManagement.enable = true;
              open = true;
              nvidiaSettings = true;
              package = config.boot.kernelPackages.nvidiaPackages.stable;
              prime = {
                inherit intelBusId nvidiaBusId;
                offload = {
                  enable = true;
                  enableOffloadCmd = true;
                };
              };
            };
          };
          services.xserver.videoDrivers = [ "nvidia" ];
        };
      })
    ];
  };
}
