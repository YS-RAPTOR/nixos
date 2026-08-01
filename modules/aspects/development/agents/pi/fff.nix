{ den, ... }: {
  den.aspects.development.agents.pi.fff.includes = [
    den.aspects.development.agents.pi.pi
    ({ user, ... }: {
      name = "pi-fff(${user.userName})";

      homeManager = { config, ... }: {
        programs.pi-coding-agent.settings.packages = [ "npm:@ff-labs/pi-fff@0.10.3" ];

        home.sessionVariables = {
          PI_FFF_MODE = "override";
          FFF_FRECENCY_DB = "${config.xdg.stateHome}/fff/frecency";
          FFF_HISTORY_DB = "${config.xdg.stateHome}/fff/history";
        };
      };
    })
  ];
}
