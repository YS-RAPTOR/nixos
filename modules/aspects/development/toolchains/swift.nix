{ inputs, ... }: {
  den.aspects.development.toolchains.swift.homeManager =
    { pkgs, ... }:
    let
      stable = import inputs.nixpkgs-stable {
        system = pkgs.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      };
    in
    {
      home.packages = [ stable.swift ];
    };
}
