{ den, ... }: {
  den.aspects.appearance.wallpaper.hyprpaper.includes = [
    den.aspects.desktop.compositor.hyprland
    ({ user, ... }: {
      name = "wallpaper(${user.userName})";

      homeManager = { lib, ... }: {
        assertions = [
          {
            assertion = user.wallpaper != null;
            message = "A wallpaper must be configured for ${user.userName}.";
          }
        ];

        services.hyprpaper = lib.mkIf (user.wallpaper != null) {
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
      };
    })
  ];
}
