{
  den.aspects.development.toolchains.python.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.python315
      pkgs.uv
    ];
  };
}
