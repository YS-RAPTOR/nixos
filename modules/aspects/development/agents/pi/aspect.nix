{ den, ... }: {
  den.batteries.development.agents.pi =
    { source }:
    let
      selectedAspect =
        {
          local = den.aspects.development.agents.pi.local-my-pi;
          github = den.aspects.development.agents.pi.my-pi;
        }
        .${source} or (throw "development.agents.pi: source must be either 'local' or 'github'");
    in
    {
      description = "Installs Pi, FFF, MCP support, and the selected my.pi package source.";
      includes = [
        den.aspects.development.agents.pi.pi
        den.aspects.development.agents.pi.fff
        den.aspects.development.agents.pi.mcp-adapter
        selectedAspect
      ];
    };
}
