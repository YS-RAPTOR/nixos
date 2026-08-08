{ ... }: {
  den.batteries.desktop.shell.panel.waybar.pia = { region }: {
    description = "Adds PIA WireGuard status and location controls to Waybar.";

    homeManager =
      {
        config,
        lib,
        pkgs,
        self',
        ...
      }:
      let
        package = self'.packages.pia-vpn;
        locationMenu = pkgs.writeShellApplication {
          name = "pia-vpn-location-menu";
          runtimeInputs = [
            package
            pkgs.jq
            pkgs.wofi
          ];
          runtimeEnv.PIA_DEFAULT_REGION = region;
          text = builtins.readFile ./_scripts/pia-location.sh;
        };
        toggle = pkgs.writeShellApplication {
          name = "pia-vpn-waybar-toggle";
          runtimeInputs = [
            package
            pkgs.ghostty
            pkgs.jq
          ];
          text = builtins.readFile ./_scripts/pia-toggle.sh;
        };
        colors = config.lib.stylix.colors;
      in
      {
        home.packages = [ package ];

        programs.waybar.settings.mainBar = {
          modules-right = lib.mkBefore [ "custom/pia-vpn" ];
          "custom/pia-vpn" = {
            exec = "${lib.getExe package} status --waybar";
            return-type = "json";
            interval = 2;
            on-click = lib.getExe toggle;
            on-click-right = lib.getExe locationMenu;
          };
        };

        programs.waybar.style = lib.mkAfter ''
          #custom-pia-vpn {
            padding: 0 5px;
          }

          #custom-pia-vpn.connected {
            color: #${colors.base0B};
          }

          #custom-pia-vpn.connecting {
            color: #${colors.base09};
          }

          #custom-pia-vpn.blocked,
          #custom-pia-vpn.setup-required {
            color: #${colors.base08};
          }

          #custom-pia-vpn.disconnected {
            color: #${colors.base03};
          }
        '';
      };
  };
}
