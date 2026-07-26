{
  den.aspects.agent.packages.homeManager = { pkgs, self', ... }: {
    home.packages = [
      pkgs.codex
      self'.packages.claude-code
      self'.packages.opencode-desktop
      self'.packages.pi
      self'.packages.t3-code
    ];
  };
}
