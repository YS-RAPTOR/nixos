{ den, ... }: {
  den.aspects.compositor.hyprland.includes = [
    den.aspects.shell.stylix
    ({ user, host, ... }: {
      name = "hyprland(${user.userName}@${host.name})";

      nixos = { pkgs, ... }: {
        programs.hyprland = {
          enable = true;
          withUWSM = true;
          xwayland.enable = true;
        };

        xdg.portal = {
          enable = true;
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        };
        systemd.user.services.xdg-desktop-portal.unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        environment.sessionVariables.NIXOS_OZONE_WL = "1";
      };

      homeManager =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          theme = pkgs.writeTextDir "lua/theme.lua" ''
            return {
                base0B = "#${config.lib.stylix.colors.base0B}",
            }
          '';

          stubs = pkgs.runCommand "hyprland-lua-stubs" { } ''
            mkdir -p "$out"
            ln -s ${pkgs.hyprland}/share/hypr/stubs "$out/stubs"
          '';

          terminalSession = pkgs.writeShellApplication {
            name = "hyprland-terminal-session";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.tmux
            ];
            text = ''
              directory="$1"
              is_terminal="$2"

              if [ "$is_terminal" = 1 ]; then
                  current=$(tmux display-message -p '#S' 2>/dev/null || true)
                  tmux_dir=$(tmux list-windows -t "$current" -F '#{pane_current_path}' 2>/dev/null | head -n 1)
                  [ -n "$tmux_dir" ] && directory=$tmux_dir
              fi

              session_base=$(basename "$directory")
              [ -n "$session_base" ] || session_base=tmux

              i=0
              while true; do
                  session=$(printf '%s-%03d' "$session_base" "$i")
                  tmux has-session -t "$session" >/dev/null 2>&1 || break
                  i=$((i + 1))
              done

              exec ${config.home.sessionVariables.TERMINAL_EXEC} tmux new-session -s "$session" -c "$directory"
            '';
          };

          runtime = pkgs.writeTextDir "lua/runtime.lua" ''
            return {
                browser = ${builtins.toJSON config.home.sessionVariables.BROWSER},
                file_manager = ${builtins.toJSON config.home.sessionVariables.FILE_MANAGER},
                hyprshot = ${builtins.toJSON (lib.getExe pkgs.hyprshot)},
                keyboard_layout = ${builtins.toJSON host.keyboardLayout},
                launcher = ${builtins.toJSON config.home.sessionVariables.APP_LAUNCHER},
                playerctl = ${builtins.toJSON (lib.getExe pkgs.playerctl)},
                private_browser = ${builtins.toJSON config.home.sessionVariables.PRIVATE_BROWSER},
                terminal_session = ${builtins.toJSON (lib.getExe terminalSession)},
                terminal_window_title = ${builtins.toJSON config.home.sessionVariables.TERMINAL_WINDOW_TITLE},
                wpctl = ${builtins.toJSON (lib.getExe' pkgs.wireplumber "wpctl")},
            }
          '';

          hyprConfig = pkgs.runCommand "hyprland-config-${user.userName}" { } ''
            mkdir -p "$out"
            cp -r ${./_config}/. "$out/"
            chmod -R u+w "$out"
            cp ${theme}/lua/theme.lua "$out/lua/theme.lua"
            cp ${runtime}/lua/runtime.lua "$out/lua/runtime.lua"
            ln -s ${stubs}/stubs "$out/stubs"
          '';
        in
        {
          xdg.portal.config.common.default = "*";

          xdg.configFile = {
            "hypr/hyprland.lua".source = "${hyprConfig}/hyprland.lua";
            "hypr/lua".source = "${hyprConfig}/lua";
            "hypr/stubs".source = "${hyprConfig}/stubs";
            "hypr/.luarc.json".source = "${hyprConfig}/.luarc.json";
          };

          home.packages = [
            pkgs.hyprshot
            pkgs.playerctl
            pkgs.wireplumber
          ];
        };
    })
  ];
}
