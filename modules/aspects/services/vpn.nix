{ den, ... }: {
  den.aspects.services.vpn = {
    includes = [ den.aspects.services.network ];
    nixos = { pkgs, ... }: {
      programs.openvpn3.enable = true;
      networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];
    };
    homeManager = { pkgs, ... }: { home.packages = [ pkgs.openvpn ]; };
  };
}
