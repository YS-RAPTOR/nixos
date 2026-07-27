{
  den.aspects.development.toolchains.java.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.maven
      pkgs.openjdk
    ];
  };
}
