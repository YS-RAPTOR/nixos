{ ... }:
let font = "monospace";
in {
  services = {
    dunst.enable = true;
    hyprpolkitagent.enable = true;
    cliphist.enable = true;
    hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };
        listener = [
          {
            timeout = 150;
            on-timeout = "brightnessctl -s set 10";
            on-resume = "brightnessctl -r";
          }
          {
            timeout = 150;
            on-timeout = "brightnessctl -sd rgb:kbd_backlight set 0";
            on-resume = "brightnessctl -rd rgb:kbd_backlight";
          }
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 330;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on && brightnessctl -r";
          }
          {
            timeout = 1800;
            on-timeout = "systemctl suspend";
          }
        ];
      };
    };
  };
  programs.hyprlock = {
    enable = true;
    settings = {
      general = { hide_cursor = false; };
      animations = {
        enabled = true;
        bezier = "linear, 1, 1, 0, 0";
        animation = [
          "fadeIn, 1, 5, linear"
          "fadeOut, 1, 5, linear"
          "inputFieldDots, 1, 2, linear"
        ];
      };
      background = {
        monitor = "";
        path = "screenshot";
        blur_passes = 3;
      };
      input-field = {
        monitor = "";
        size = "20%, 5%";
        outline_thickness = 3;
        inner_color = "rgba(0, 0, 0, 0.0)"; # no fill
        outer_color = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        check_color = "rgba(00ff99ee) rgba(ff6633ee) 120deg";
        fail_color = "rgba(ff6633ee) rgba(ff0066ee) 40deg";
        font_color = "rgb(143, 143, 143)";
        fade_on_empty = false;
        rounding = 15;
        font_family = font;
        placeholder_text = "Input password...";
        fail_text = "$PAMFAIL";
        dots_spacing = 0.3;
        position = "0, -20";
        halign = "center";
        valign = "center";
      };
      label = [
        {
          monitor = "";
          text = "$TIME";
          font_size = 90;
          font_family = font;
          position = "-30, 0";
          halign = "right";
          valign = "top";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] date +"%A, %d %B %Y"'';
          font_size = 25;
          font_family = font;
          position = "-30, -150";
          halign = "right";
          valign = "top";
        }
      ];
    };
  };
}

