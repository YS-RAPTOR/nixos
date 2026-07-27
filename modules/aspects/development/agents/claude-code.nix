{
  den.aspects.development.agents.claude-code.homeManager = { self', ... }: {
    home.packages = [ self'.packages.claude-code ];
  };
}
