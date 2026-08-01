{
  den.aspects.development.agents.pi.local-my-pi.homeManager = { config, ... }: {
    programs.pi-coding-agent.settings.packages = [ "${config.home.homeDirectory}/Dev/my.pi" ];
  };
}
