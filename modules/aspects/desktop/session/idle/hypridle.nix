{ den, ... }: {
  den.aspects.desktop.session.idle.hypridle = {
    includes = [
      den.aspects.desktop.compositor.hyprland
      den.aspects.desktop.session.lock.hyprlock
    ];
    homeManager = { lib, pkgs, ... }: {
      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "${lib.getExe' pkgs.procps "pidof"} hyprlock || ${lib.getExe pkgs.hyprlock}";
            before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
            after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
          };

          listener = [
            {
              timeout = 120;
              on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
            }
            {
              timeout = 180;
              on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
              on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on && display-brightness restore";
            }
            {
              timeout = 300;
              on-timeout = "${pkgs.systemd}/bin/systemctl suspend";
            }
          ];
        };
      };
    };
  };
}
