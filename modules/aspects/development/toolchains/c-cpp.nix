{
  den.aspects.development.toolchains.c-cpp.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.gcc
      pkgs.pkg-config
    ];
  };
}
