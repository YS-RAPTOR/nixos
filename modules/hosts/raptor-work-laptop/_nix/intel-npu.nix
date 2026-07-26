{ modulesPath, ... }: {
  imports = [ (modulesPath + "/hardware/cpu/intel-npu.nix") ];

  hardware.cpu.intel.npu.enable = true;
}
