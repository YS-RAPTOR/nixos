{
  den.aspects.development.tools.devops.homeManager = { pkgs, self', ... }: {
    home.packages = [
      pkgs.tilt
      self'.packages.wombat
    ];
  };
}
