{
  den.aspects.tooling.devops.homeManager = { pkgs, self', ... }: {
    home.packages = [
      pkgs.tilt
      self'.packages.wombat
    ];
  };
}
