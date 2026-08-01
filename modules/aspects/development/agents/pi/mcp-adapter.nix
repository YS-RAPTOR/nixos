{ den, ... }: {
  den.aspects.development.agents.pi.mcp-adapter.includes = [
    den.aspects.development.agents.pi.pi
    ({ user, ... }: {
      name = "pi-mcp-adapter(${user.userName})";

      homeManager = {
        programs.pi-coding-agent.settings.packages = [ "npm:pi-mcp-adapter@2.17.0" ];

        xdg.configFile."mcp/mcp.json".text = builtins.toJSON {
          settings = {
            toolPrefix = "server";
            idleTimeout = 10;
            showStatusIcon = true;
            mcpFooterStatus = "compact";
            hostConfigDiscovery = "off";
            directTools = false;
            disableProxyTool = false;
            autoAuth = false;
            sampling = true;
            samplingAutoApprove = false;
            elicitation = true;
            outputGuard = {
              maxBytes = 51200;
              maxLines = 2000;
              detailsMaxBytes = 16384;
            };
            trace.enabled = false;
          };
          mcpServers = { };
        };
      };
    })
  ];
}
