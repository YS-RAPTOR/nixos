{

	description = "Raptor's System Configuration";
	inputs = {
		nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
		home-manager-unstable.url = "github:nix-community/home-manager/master";
		home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";

		nixpkgs-stable.url = "nixpkgs/nixos-25.05";
		home-manager-stable.url = "github:nix-community/home-manager/release-25.05";
		home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";
	};	outputs = inputs@{self, ...} :
		let 
			systemSettings = {
				system = "x86_64-linux";
				hostname = "raptor-laptop";
				timezone = "Australia/Melbourne";
				locale = "en_AU.UTF-8";
				unstable = true;
			};
			userSettings = {
				username = "raptor";
				github-username = "YS-Raptor";
				name = "Yashan";
				email = "yashan.sumanaratne@gmail.com";
				# font, fontPkg
			};
			pkgs-unstable = import inputs.nixpkgs-unstable {
				system = systemSettings.system;
				config = {
					allowUnfree = true;
					allowUnfreePredicate = (_: true);
				};
			};
			pkgs-stable = import inputs.nixpkgs-stable {
				system = systemSettings.system;
				config = {
					allowUnfree = true;
					allowUnfreePredicate = (_: true);
				};
			};

			lib = if systemSettings.unstable then inputs.nixpkgs-unstable.lib else inputs.nixpkgs-stable.lib;
			home-manager = if systemSettings.unstable then inputs.home-manager-unstable else inputs.home-manager-stable; 
			pkgs = if systemSettings.unstable then pkgs-unstable else pkgs-stable; 

		in {
			nixosConfigurations = {
				raptor-laptop = lib.nixosSystem {
					system = systemSettings.system;
					modules = [ ./configurations.nix ];
				};
			};
			homeConfigurations = {
				${userSettings.username} = home-manager.lib.homeManagerConfiguration {
					inherit pkgs;
					modules = [ ./home.nix ];
				};
			};
		};
}
