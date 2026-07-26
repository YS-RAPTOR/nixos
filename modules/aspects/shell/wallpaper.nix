{ den, ... }: {
  den.aspects.shell.wallpaper.includes = [
    den.aspects.compositor.hyprland
    ({ user, ... }: {
      name = "wallpaper(${user.userName})";

      homeManager.services.hyprpaper = {
        enable = true;
        settings = {
          ipc = "on";
          splash = false;
          splash_offset = 2;
          wallpaper = [
            {
              monitor = "";
              path = toString user.wallpaper;
              fit_mode = "cover";
            }
          ];
        };
      };
    })
  ];
}
