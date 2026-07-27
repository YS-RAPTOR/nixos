{ den, ... }: {
  den.batteries.programs.file-manager.defaults = {
    nautilus = {
      includes = [ den.aspects.programs.file-manager.nautilus ];
      homeManager.desktop.commands.fileManager = "nautilus";
    };

    yazi = {
      includes = [ den.aspects.programs.file-manager.yazi ];
      homeManager.desktop.commands.fileManager = "yazi";
    };
  };
}
