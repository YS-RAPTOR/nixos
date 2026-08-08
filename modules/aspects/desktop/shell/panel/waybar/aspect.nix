{ den, inputs, ... }: {
  den.aspects.desktop.shell.panel.waybar = {
    includes = [
      den.aspects.desktop.compositor.hyprland
      den.aspects.appearance.theme.stylix
      den.aspects.services.networking.networkmanager
      den.aspects.services.audio.pipewire
      den.aspects.services.bluetooth
    ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        colors = config.lib.stylix.colors;

        tmuxStatus = pkgs.writeShellApplication {
          name = "waybar-tmux-status";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.jq
            pkgs.tmux
          ];
          text = builtins.readFile ./_scripts/tmux.sh;
        };

        colorpicker = pkgs.writeShellApplication {
          name = "waybar-colorpicker";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.hyprpicker
            pkgs.jq
            pkgs.libnotify
            pkgs.procps
            pkgs.wl-clipboard
          ];
          text = builtins.readFile ./_scripts/colorpicker.sh;
        };

        bluetoothMenu = pkgs.writeShellApplication {
          name = "waybar-bluetooth";
          runtimeInputs = [
            pkgs.bluez
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.util-linux
            pkgs.wofi
          ];
          text = builtins.readFile ./_scripts/wofi-bluetooth.sh;
        };

        clipboardMenu = pkgs.writeShellApplication {
          name = "waybar-clipboard";
          runtimeInputs = [
            pkgs.cliphist
            pkgs.wl-clipboard
            pkgs.wofi
          ];
          text = ''
            cliphist list | wofi --dmenu | cliphist decode | wl-copy
          '';
        };
      in
      {
        stylix.targets.waybar.enable = false;

        services.cliphist.enable = true;

        home.packages = [
          pkgs.networkmanager_dmenu
          pkgs.pavucontrol
          pkgs.wireplumber
          pkgs.wl-clipboard
          pkgs.wofi
        ];

        xdg.configFile."networkmanager-dmenu/config.ini".text = ''
          [dmenu]
          dmenu_command = ${lib.getExe pkgs.wofi} --dmenu
          highlight = True
          prompt = Networks
        '';

        programs.waybar = {
          enable = true;
          package = inputs.waybar.packages.${pkgs.stdenv.hostPlatform.system}.default;
          systemd.enable = true;

          settings.mainBar = {
            layer = "top";
            position = "top";
            reload_style_on_change = true;

            modules-left = [
              "custom/logo"
              "clock"
            ];
            modules-center = [ "hyprland/workspaces" ];
            modules-right = [
              "tray"
              "custom/clipboard"
              "backlight"
              "custom/colorpicker"
              "bluetooth"
              "pulseaudio"
              "network"
              "battery"
            ];

            "hyprland/workspaces" = {
              format = "{icon}";
              on-click = "activate";
              format-icons = {
                active = "";
                visible = "";
                persistent = "";
                empty = "";
                default = "";
              };
            };

            "custom/logo" = {
              format = "{}";
              return-type = "json";
              exec = "${tmuxStatus}/bin/waybar-tmux-status";
            };

            clock = {
              tooltip = false;
              interval = 1;
              format = "{:%a %d %b %Y 󰥔 %H:%M}";
            };

            "custom/clipboard" = {
              format = "";
              on-click = lib.getExe clipboardMenu;
            };

            backlight = {
              device = "intel_backlight";
              tooltip = false;
              format = "<span font='12'>{icon}</span>";
              format-icons = [
                ""
                ""
                ""
                ""
                ""
                ""
                ""
                ""
                ""
                ""
                ""
                ""
                ""
                ""
              ];
              on-scroll-down = "display-brightness down";
              on-scroll-up = "display-brightness up";
              smooth-scrolling-threshold = 1;
            };

            "custom/colorpicker" = {
              format = "{}";
              return-type = "json";
              interval = "once";
              exec = "${colorpicker}/bin/waybar-colorpicker --json";
              on-click = "${colorpicker}/bin/waybar-colorpicker";
              signal = 1;
            };

            bluetooth = {
              format-on = "";
              format-off = "";
              format-disabled = "󰂲";
              format-connected = "󰂴";
              format-connected-battery = "{device_battery_percentage}% 󰂴";
              tooltip-format = ''
                {controller_alias}	{controller_address}

                {num_connections} connected'';
              tooltip-format-connected = ''
                {controller_alias}	{controller_address}

                {num_connections} connected

                {device_enumerate}'';
              tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
              tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
              on-click = "${bluetoothMenu}/bin/waybar-bluetooth";
            };

            pulseaudio = {
              format = "{volume}% {icon}";
              format-bluetooth = "{volume}% 󰂰";
              format-muted = "<span font='12'></span>";
              format-icons = {
                headphones = "";
                bluetooth = "󰥰";
                handsfree = "";
                headset = "󱡬";
                phone = "";
                portable = "";
                car = "";
                default = [
                  "🕨"
                  "🕩"
                  "🕪"
                ];
              };
              justify = "center";
              on-click = "${lib.getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SINK@ toggle";
              on-click-right = lib.getExe pkgs.pavucontrol;
              tooltip-format = "{icon} {volume}%";
            };

            network = {
              format-wifi = "";
              format-ethernet = "";
              format-disconnected = "";
              tooltip-format = "{ipaddr}";
              tooltip-format-wifi = "{essid} ({signalStrength}%)  | {ipaddr}";
              tooltip-format-ethernet = "{ifname} 🖧 | {ipaddr}";
              on-click = lib.getExe pkgs.networkmanager_dmenu;
            };

            battery = {
              interval = 1;
              states = {
                good = 95;
                warning = 30;
                critical = 20;
              };
              format = "{capacity}% {icon}";
              format-charging = "{capacity}% 󰂄";
              format-plugged = "{capacity}% 󰂄 ";
              format-icons = [
                "󰁻"
                "󰁼"
                "󰁾"
                "󰂀"
                "󰂂"
                "󰁹"
              ];
            };

            tray = {
              icon-size = 14;
              spacing = 10;
            };
          };

          style = ''
            * {
              border: none;
              font-size: 14px;
              font-family: "${config.stylix.fonts.monospace.name}";
              min-height: 15px;
              color: #${colors.base04};
            }

            #tray menu {
              background-color: #${colors.base00};
              color: #${colors.base04};
            }

            #tray menuitem:hover {
              background-color: #${colors.base03};
            }

            window#waybar {
              background: rgba(0, 0, 0, 0);
              margin: 5px;
            }

            #custom-logo {
              padding: 0 20px;
              border-radius: 0 15px 15px 0;
              margin-right: 5px;
              color: #${colors.base02};
              font-weight: 900;
            }

            #custom-logo.active {
              background: #${colors.base09};
            }

            #custom-logo.inactive {
              background: #${colors.base0B};
            }

            .modules-right {
              padding-left: 5px;
              border-radius: 15px 0 0 15px;
              margin-top: 2px;
              background: #${colors.base00};
            }

            .modules-center {
              padding: 0 15px;
              margin-top: 2px;
              border-radius: 15px;
              background: #${colors.base00};
            }

            .modules-left {
              border-radius: 0 15px 15px 0;
              padding-right: 5px;
              margin-top: 2px;
              background: #${colors.base00};
            }

            #battery,
            #custom-clipboard,
            #custom-colorpicker,
            #bluetooth,
            #pulseaudio,
            #network,
            #backlight,
            #tray,
            #window,
            #workspaces,
            #clock {
              padding: 0 5px;
            }

            #pulseaudio,
            #pulseaudio.muted {
              padding-top: 3px;
            }

            #pulseaudio.muted {
              color: #${colors.base08};
            }

            #clock {
              color: #${colors.base0C};
            }

            #battery.charging {
              color: #${colors.base04};
              background-color: #${colors.base0B};
            }

            #battery.warning:not(.charging) {
              background-color: #${colors.base09};
              color: black;
            }

            #battery.critical:not(.charging) {
              background-color: #${colors.base08};
              color: #${colors.base04};
              animation-name: blink;
              animation-duration: 0.5s;
              animation-timing-function: linear;
              animation-iteration-count: infinite;
              animation-direction: alternate;
            }

            @keyframes blink {
              to {
                background-color: #${colors.base04};
                color: #${colors.base00};
              }
            }
          '';
        };
      };
  };
}
