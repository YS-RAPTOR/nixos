{
    pkgs,
    lib,
    config,
    settings,
    ...
}:
let
    brightness = import ../../lib/brightness.nix { inherit settings; };

    terminal = pkgs.writeShellScript "ghostty" ''
        WINDOW=$(hyprctl activewindow -j | jq -r '.initialTitle')

        if [ "$WINDOW" == "Ghostty" ]; then
          CURRENT=$(tmux display-message -p '#S')
          DIRECTORY=$(
            tmux list-windows -t "$CURRENT" -F '#{pane_current_path}' | head -n 1
          )
        else
          DIRECTORY="${settings.user.homeDir}"
        fi

        SESSION=$(basename "$DIRECTORY")


        i=0
        while true; do
            FINAL=$(printf "$SESSION-%03d" "$i")
            if ! tmux has-session -t "$FINAL" 2>/dev/null; then
                break
            fi
            i=$((i + 1))
        done
        ghostty -e tmux new-session -s "$FINAL" -c "$DIRECTORY"
    '';

    scrollOrDefault = pkgs.writeShellScript "scroll-or-default" ''
        LAYOUT=$(hyprctl activeworkspace -j | jq -r '.tiledLayout')
        if [ "$LAYOUT" = "scrolling" ]; then
            hyprctl dispatch $1
        else
            if [ -n "$2" ]; then
                hyprctl dispatch $2
            fi
        fi
    '';

    toggleScrollColsize = pkgs.writeShellScript "toggle-scroll-colsize" ''
        LAYOUT=$(hyprctl activeworkspace -j | jq -r '.tiledLayout')

        if [ "$LAYOUT" != "scrolling" ]; then
            hyprctl dispatch fullscreen
            exit 0
        fi

        MONITOR=$(hyprctl activeworkspace -j | jq -r '.monitor')
        MONITOR_WIDTH=$(hyprctl monitors -j | jq -r ".[] | select(.name == \"$MONITOR\") | (.width / .scale | floor)")
        WINDOW_WIDTH=$(hyprctl activewindow -j | jq -r '.size[0]')

        if [ -z "$MONITOR_WIDTH" ] || [ "$MONITOR_WIDTH" -le 0 ] || [ -z "$WINDOW_WIDTH" ]; then
            exit 0
        fi

        if [ $((WINDOW_WIDTH * 100)) -ge $((MONITOR_WIDTH * 75)) ]; then
            hyprctl dispatch layoutmsg "colresize 0.5"
        else
            hyprctl dispatch layoutmsg "colresize 1.0"
        fi
    '';

    workspaceBinds =
        workspaces:
        lib.flatten (
            map (ws: [
                "$mainMod ${ws.keyModifier}, ${ws.key}, workspace, name:${ws.name}"
                "$mainMod ${ws.keyModifier} SHIFT, ${ws.key}, movetoworkspace, name:${ws.name}"
            ]) workspaces
        );

in
{
    wayland.windowManager.hyprland = {
        enable = true;
        package = null;
        systemd.enable = false;

        settings = {
            env = [ "XDG_CURRENT_DESKTOP,Hyprland" ];
            monitor = settings.wm.monitors;
            exec-once = settings.wm.startup pkgs;

            "$terminal" = "${terminal}";
            "$scrollOrDefault" = "${scrollOrDefault}";
            "$toggleScrollColsize" = "${toggleScrollColsize}";
            "$menu" = "wofi --show drun";
            "$browser" = "vivaldi";
            "$fileManager" = "nautilus";

            general = {
                border_size = 2;
                gaps_in = 4;
                gaps_out = 4;
                "col.active_border" = lib.mkForce "rgb(${config.lib.stylix.colors.base0B})";
                resize_on_border = false;
                allow_tearing = false;
                layout = "dwindle";
            };

            group = {
                groupbar = {
                    "col.active" = lib.mkForce "rgb(${config.lib.stylix.colors.base0B})";
                };
                "col.border_active" = lib.mkForce "rgb(${config.lib.stylix.colors.base0B})";
            };

            decoration = {
                rounding = 1;
                rounding_power = 4;
                active_opacity = 1.0;
                inactive_opacity = 1.0;
                shadow = {
                    enabled = true;
                    range = 4;
                    render_power = 3;
                };

                blur = {
                    enabled = true;
                    size = 5;
                    passes = 2;
                    vibrancy = 0.1696;
                };
            };
            layerrule = {
                name = "waybar-blur";
                blur = "on";
                "match:namespace" = "waybar";
            };
            blurls = "waybar";

            animations = {
                enabled = "yes";
                bezier = [
                    "easeOutQuint,0.23,1,0.32,1"
                    "easeInOutCubic,0.65,0.05,0.36,1"
                    "linear,0,0,1,1"
                    "almostLinear,0.5,0.5,0.75,1.0"
                    "quick,0.15,0,0.1,1"
                ];

                animation = [
                    "global, 1, 10, default"
                    "border, 1, 5.39, easeOutQuint"
                    "windows, 1, 4.79, easeOutQuint"
                    "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
                    "windowsOut, 1, 1.49, linear, popin 87%"
                    "fadeIn, 1, 1.73, almostLinear"
                    "fadeOut, 1, 1.46, almostLinear"
                    "fade, 1, 3.03, quick"
                    "layers, 1, 3.81, easeOutQuint"
                    "layersIn, 1, 4, easeOutQuint, fade"
                    "layersOut, 1, 1.5, linear, fade"
                    "fadeLayersIn, 1, 1.79, almostLinear"
                    "fadeLayersOut, 1, 1.39, almostLinear"
                    "workspaces, 1, 1.94, almostLinear, fade"
                    "workspacesIn, 1, 1.21, almostLinear, fade"
                    "workspacesOut, 1, 1.94, almostLinear, fade"
                ];
            };

            workspace = [
                "w[tv1], gapsout:0, gapsin:0"
                "f[1], gapsout:0, gapsin:0"
            ]
            ++ (builtins.map (ws: ws.rule) settings.wm.workspaces);

            windowrule = [
                {
                    name = "suppress-maximize";
                    suppress_event = "maximize";
                    "match:class" = ".*";
                }
                {
                    name = "xwayland-ghosts";
                    no_focus = "on";
                    "match:class" = "^$";
                    "match:title" = "^$";
                    "match:xwayland" = 1;
                    "match:float" = 1;
                    "match:fullscreen" = 0;
                    "match:pin" = 0;
                }
                {
                    name = "when-one-tiling-window";
                    border_size = 0;
                    rounding = 0;
                    "match:float" = 0;
                    "match:workspace" = "w[tv1]";
                }
                {
                    name = "when-one-fullscreen-window";
                    border_size = 0;
                    rounding = 0;
                    "match:float" = 0;
                    "match:workspace" = "f[1]";
                }
            ];

            dwindle = {
                pseudotile = true;
                preserve_split = true;
            };

            master = {
                new_status = "master";
            };

            misc = {
                force_default_wallpaper = -1;
                disable_hyprland_logo = false;
            };

            xwayland = {
                force_zero_scaling = true;
            };

            input = {
                kb_layout = "us";
                kb_variant = "";
                kb_model = "";
                kb_options = "";
                kb_rules = "";

                follow_mouse = 1;
                numlock_by_default = true;
                sensitivity = 0;
                accel_profile = "flat";
                touchpad = {
                    natural_scroll = true;
                    disable_while_typing = true;

                };
            };

            gesture = [
                "3, up, dispatcher, workspace, e-1"
                "3, down, dispatcher, workspace, e+1"
                "3, right, dispatcher, exec, $scrollOrDefault 'layoutmsg focus l' ''"
                "3, left, dispatcher, exec, $scrollOrDefault 'layoutmsg focus r' ''"
                "4, swipe, move"
            ];

            device = {
                name = "epic-mouse-v1";
                sensitivity = -0.5;
            };

            "$mainMod" = "SUPER";

            bind = [
                "$mainMod, W, killactive,"
                "$mainMod, Q, exec, $terminal"
                "$mainMod, E, exec, $fileManager"
                "$mainMod, R, exec, $menu"
                "$mainMod, D, exec, $browser"
                "$mainMod SHIFT, D, exec, $browser -incognito"

                "$mainMod SHIFT, P, pseudo,"
                "$mainMod SHIFT, A, togglesplit,"

                "$mainMod, T, togglefloating,"
                "$mainMod, F, exec, $toggleScrollColsize"
                "$mainMod, A, fullscreen,"
                "$mainMod, G, layoutmsg, colresize +conf"
                "$mainMod, P, layoutmsg, promote"

                # Screenshot a monitor
                "$mainMod SHIFT, S, exec, hyprshot -z -m output"
                " , PRINT, exec, hyprshot -z -m output"
                # Screenshot a window
                "CONTROL, PRINT, exec, hyprshot -z -m window"
                # Screenshot a region
                "SHIFT, PRINT, exec, hyprshot -z -m region"

                # Move focus with mainMod + arrow keys
                "$mainMod, H, exec, $scrollOrDefault 'layoutmsg focus l' 'movefocus l'"
                "$mainMod, L, exec, $scrollOrDefault 'layoutmsg focus r' 'movefocus r'"
                "$mainMod, K, exec, $scrollOrDefault 'layoutmsg focus u' 'movefocus u'"
                "$mainMod, J, exec, $scrollOrDefault 'layoutmsg focus d' 'movefocus d'"

                # Swap Window
                "$mainMod SHIFT, H, exec, $scrollOrDefault 'layoutmsg swapcol l' 'swapwindow l'"
                "$mainMod SHIFT, L, exec, $scrollOrDefault 'layoutmsg swapcol r' 'swapwindow r'"
                "$mainMod SHIFT, K, exec, $scrollOrDefault 'swapwindow u' 'swapwindow u'"
                "$mainMod SHIFT, J, exec, $scrollOrDefault 'swapwindow d' 'swapwindow d'"

                # Resize Window
                "$mainMod CONTROL, H, resizeactive, -10 0"
                "$mainMod CONTROL, L, resizeactive, 10 0"
                "$mainMod CONTROL, K, resizeactive, 0 -10"
                "$mainMod CONTROL, J, resizeactive, 0 10"

                # Example special workspace (scratchpad)
                "$mainMod, S, togglespecialworkspace, magic"
                "$mainMod CONTROL, S, movetoworkspace, special:magic"
            ]
            ++ (workspaceBinds settings.wm.workspaces);

            # Laptop multimedia keys for volume and LCD brightness
            bindel = [
                ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
                ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
                ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
                ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
                ",XF86MonBrightnessUp, exec, ${brightness.set "5%+"}"
                ",XF86MonBrightnessDown, exec, ${brightness.set "5%-"}"
            ];

            # Requires playerctl
            bindl = [
                ", XF86AudioNext, exec, playerctl next"
                ", XF86AudioPause, exec, playerctl play-pause"
                ", XF86AudioPlay, exec, playerctl play-pause"
                ", XF86AudioPrev, exec, playerctl previous"
            ];

            bindm = [
                # Move/resize windows with mainMod + LMB/RMB and dragging
                "$mainMod, mouse:272, movewindow"
                "$mainMod, mouse:273, resizewindow"
            ];
        };
    };
}
