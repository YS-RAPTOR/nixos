{ den, ... }: {
  den.aspects.desktop.compositor.hyprland.includes = [
    den.aspects.appearance.theme.stylix
    den.aspects.services.audio.pipewire
    den.aspects.terminal.ghostty
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

          runtime = pkgs.writeTextDir "lua/runtime.lua" ''
            return {
                browser = ${builtins.toJSON config.desktop.commands.browser},
                file_manager = ${builtins.toJSON config.desktop.commands.fileManager},
                hyprshot = ${builtins.toJSON (lib.getExe pkgs.hyprshot)},
                keyboard_layout = ${builtins.toJSON host.keyboardLayout},
                launcher = ${builtins.toJSON config.desktop.commands.launcher},
                playerctl = ${builtins.toJSON (lib.getExe pkgs.playerctl)},
                private_browser = ${builtins.toJSON config.desktop.commands.privateBrowser},
                terminal = ${builtins.toJSON (lib.getExe config.programs.ghostty.package)},
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
          assertions =
            map
              (command: {
                assertion = command.value != null;
                message = "A default ${command.name} must be selected for Hyprland.";
              })
              [
                {
                  name = "browser";
                  value = config.desktop.commands.browser;
                }
                {
                  name = "private browser";
                  value = config.desktop.commands.privateBrowser;
                }
                {
                  name = "file manager";
                  value = config.desktop.commands.fileManager;
                }
                {
                  name = "launcher";
                  value = config.desktop.commands.launcher;
                }
              ];

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
