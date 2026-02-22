{
    settings,
    lib,
    config,
    ...
}:
let
    font = "monospace";
    brightness = import ../../lib/brightness.nix { inherit settings; };
in
{
    services = {
        hyprpaper = {
            enable = true;
            settings = {
                ipc = "on";
                splash = false;
                splash_offset = 2;
                wallpaper = [
                    {
                        monitor = "";
                        path = "${settings.user.wallpaper}";
                        fit_mode = "cover";
                    }
                ];
            };
        };

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
                        timeout = 60;
                        on-timeout = brightness.save "1%";
                        on-resume = brightness.restore;
                    }
                    {
                        timeout = 60;
                        on-timeout = "brightnessctl -sd ${settings.hardware.keyboard.backlight.device} set 0";
                        on-resume = "brightnessctl -rd ${settings.hardware.keyboard.backlight.device}";
                    }
                    {
                        timeout = 120;
                        on-timeout = "loginctl lock-session";
                    }
                    {
                        timeout = 180;
                        on-timeout = "hyprctl dispatch dpms off";
                        on-resume = "hyprctl dispatch dpms on && brightnessctl -r";
                    }
                    {
                        timeout = 300;
                        on-timeout = "systemctl suspend";
                    }
                ];
            };
        };
    };

    programs.hyprlock = {
        enable = true;
        settings = {
            general = {
                hide_cursor = false;
            };
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
                outer_color = lib.mkForce "rgb(${config.lib.stylix.colors.base0B})";
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
