{ userSettings, ... }: {
  programs.bat = {
    enable = true;
    config = { theme = "tokyonight_night"; };
    themes = {
      tokyonight_night = {
        src = "${userSettings.nixDir}/themes";
        file = "tokyonight_night.tmTheme";
      };
    };
  };
}
