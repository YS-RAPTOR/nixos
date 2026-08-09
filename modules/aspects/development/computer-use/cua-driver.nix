{ den, inputs, ... }: {
  den.aspects.development.computer-use.cua-driver.nixos =
    { lib, pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      cuaDriver = inputs.self.packages.${system}.cua-driver;
    in
    {
      imports = [ inputs.cua.nixosModules.cua-driver ];

      services.cua-driver = {
        enable = true;
        package = cuaDriver;
      };

      environment = {
        systemPackages = [ inputs.cua.packages.${system}.cua-compositor ];
        variables = {
          CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
          CUA_DRIVER_RS_TELEMETRY_ENABLED = "false";
          NO_AT_BRIDGE = lib.mkForce "0";
        };
      };
    };
}
