{

  description = "Raptor's NixOS Configuration";
  inputs = {
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    home-manager-unstable.url = "github:nix-community/home-manager/master";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
    stylix-unstable.url = "github:nix-community/stylix/master";
    stylix-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nixpkgs-stable.url = "nixpkgs/nixos-25.05";
    home-manager-stable.url = "github:nix-community/home-manager/release-25.05";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";
    stylix-stable.url = "github:nix-community/stylix/release-25.05";
    stylix-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    affinity-nix.url = "path:./local-flakes/affinity-nix";
    wombat.url = "path:./local-flakes/wombat";
  };
  outputs = inputs@{ self, affinity-nix, wombat, ... }:
    let
      profile = "home";
      settings = import ./profiles/${profile}/zzz.nix;
      overlays = import ./overlays/zzz.nix;

      pkgs-unstable = import inputs.nixpkgs-unstable {
        system = settings.system.target;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
        inherit overlays;
      };
      pkgs-stable = import inputs.nixpkgs-stable {
        system = settings.system.target;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
        inherit overlays;
      };

      channel = if settings.system.unstable then "unstable" else "stable";
      lib = inputs."nixpkgs-${channel}".lib;
      home-manager = inputs."home-manager-${channel}";
      pkgs = if settings.system.unstable then pkgs-unstable else pkgs-stable;
      stylix = inputs."stylix-${channel}";

      extra = {
        affinity = affinity-nix.packages.${settings.system.target}.v3;
        wombat = wombat.packages.${settings.system.target}.wombat;
      };
    in {
      nixosConfigurations = {
        ${settings.system.hostname} = lib.nixosSystem {
          system = settings.system.target;
          modules = [
            ./system/zzz.nix
            stylix.nixosModules.stylix
            home-manager.nixosModules.home-manager
            { nixpkgs.pkgs = pkgs; }
            {
              home-manager = {
                users.${settings.user.username} = ./home/zzz.nix;
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit pkgs-stable;
                  inherit settings;
                  inherit inputs;
                  inherit extra;
                };
              };
            }
          ];
          specialArgs = {
            inherit pkgs-stable;
            inherit settings;
            inherit inputs;
            inherit extra;
          };
        };
      };
    };
}
