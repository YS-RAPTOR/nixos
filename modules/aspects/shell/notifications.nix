{ den, ... }: {
  den.aspects.shell.notifications = {
    includes = [ den.aspects.shell.stylix ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        home.packages = [ pkgs.libnotify ];

        services.dunst = {
          enable = true;
          settings = {
            global.follow = "keyboard";
            urgency_normal.frame_color = lib.mkForce "#${config.lib.stylix.colors.base0B}";
          };
        };
      };
  };
}
