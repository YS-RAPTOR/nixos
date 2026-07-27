{
  den.aspects.development.version-control.github-cli.homeManager = { self', ... }: {
    home.packages = [ self'.packages.gh ];
  };
}
