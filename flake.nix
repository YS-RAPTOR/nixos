{

	description = "System Configuration";
	inputs = {
		nixpkgs.url = "nixpkgs/nixos-unstable";
		nixpkgs-stable.url = "nixpkgs/nixos-25.05";
	};
	outputs = {self, nixpkgs, ...} :
		let 
			lib = nixpkgs.lib;
		in {
			nixosConfigurations = {
				raptorlaptop = lib.nixosSystem {
					system = "x86_64-linux";
					modules = [ ./configurations.nix ];
				};
			};

		};
}