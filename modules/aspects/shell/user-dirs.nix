{
  den.aspects.shell.user-dirs.homeManager =
    { config, ... }:
    let
      home = config.home.homeDirectory;
    in
    {
      xdg.userDirs = {
        enable = true;
        createDirectories = true;
        setSessionVariables = true;
        desktop = "${home}/Desktop";
        download = "${home}/Downloads";
        documents = "${home}/Documents";
        music = "${home}/Music";
        pictures = "${home}/Pictures";
        videos = "${home}/Videos";
        publicShare = "${home}/Public";
        projects = null;
        templates = null;
      };
    };
}
