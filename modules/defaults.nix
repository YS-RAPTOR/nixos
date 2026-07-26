{ lib, den, ... }: {
  den.default = {
    nixos = {
      system.stateVersion = "26.05";
      nixpkgs.config.allowUnfree = true;

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
      };
    };

    homeManager.home.stateVersion = "26.05";

    includes = [
      den.batteries.hostname
      den.batteries.define-user
      den.batteries.inputs'
      den.batteries.self'
    ];
  };

  den.schema.user.classes = lib.mkDefault [ "homeManager" ];
}
