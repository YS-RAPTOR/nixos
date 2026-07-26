{ inputs, lib, ... }: {
  imports = [
    (inputs.flake-file.flakeModules.dendritic or { })
    (inputs.den.flakeModules.dendritic or { })
    inputs.pkgs-by-name-for-flake-parts.flakeModule
  ];

  flake-file.inputs = {
    den.url = lib.mkDefault "github:denful/den";
    flake-file.url = lib.mkDefault "github:vic/flake-file";
    pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";
  };

  perSystem = { system, ... }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    pkgsDirectory = ../packages;
  };
}
