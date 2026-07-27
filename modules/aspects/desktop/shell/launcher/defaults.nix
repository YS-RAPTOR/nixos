{ den, ... }: {
  den.batteries.desktop.shell.launcher.defaults.wofi = {
    includes = [ den.aspects.desktop.shell.launcher.wofi ];
    homeManager.desktop.commands.launcher = "wofi --show drun";
  };
}
