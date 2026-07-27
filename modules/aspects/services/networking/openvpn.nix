{ den, ... }: {
  den.aspects.services.networking.openvpn = {
    includes = [ den.aspects.services.networking.networkmanager ];
    nixos = { pkgs, ... }: {
      programs.openvpn3.enable = true;
      networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];
    };
    homeManager = { pkgs, ... }: { home.packages = [ pkgs.openvpn ]; };
  };
}
