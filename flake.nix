{

    description = "Raptor's NixOS Configuration";
    inputs = {
        nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
        home-manager-unstable.url = "github:nix-community/home-manager/master";
        home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
        stylix-unstable.url = "github:nix-community/stylix/master";
        stylix-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";

        nixpkgs-stable.url = "nixpkgs/nixos-26.05";
        home-manager-stable.url = "github:nix-community/home-manager/release-26.05";
        home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";
        stylix-stable.url = "github:nix-community/stylix/release-25.11";
        stylix-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

        local-flakes.url = "path:./local-flakes";
        local-flakes.inputs.nixpkgs.follows = "nixpkgs-unstable";

        waybar.url = "github:Alexays/Waybar/master";
        waybar.inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    outputs =
        inputs@{
            self,
            local-flakes,
            waybar,
            ...
        }:
        let
            profile = "home";
            settings = import ./profiles/${profile}/zzz.nix;
            overlays = [ waybar.overlays.default ] ++ import ./overlays/zzz.nix;

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

            extra = local-flakes.packages.${settings.system.target};
        in
        {
            packages.${settings.system.target} = local-flakes.packages.${settings.system.target};

            formatter.${settings.system.target} = pkgs.writeShellApplication {
                name = "nixfmt";
                runtimeInputs = [
                    pkgs.nixfmt
                    pkgs.findutils
                ];
                text = ''
                    if [ "$#" -eq 0 ]; then
                        find . -type f -name '*.nix' -print0 | xargs -0 -r nixfmt --indent 4
                        exit 0
                    fi

                    exec nixfmt --indent 4 "$@"
                '';
            };

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
