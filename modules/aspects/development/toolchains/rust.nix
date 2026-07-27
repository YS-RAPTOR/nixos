{
  den.aspects.development.toolchains.rust.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.cargo
      pkgs.rust-analyzer
      pkgs.rustc
    ];
  };
}
