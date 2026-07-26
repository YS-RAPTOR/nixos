{ den, ... }: {
  den.aspects.shell.startup.includes = [
    den.aspects.compositor.hyprland
    den.aspects.services.pipewire
    ({ user, ... }: {
      name = "startup(${user.userName})";

      homeManager =
        { lib, pkgs, ... }:
        let
          dependencies = [
            "pipewire.service"
            "wireplumber.service"
            "xdg-desktop-portal.service"
            "xdg-desktop-portal-hyprland.service"
            "xdg-desktop-portal-gtk.service"
          ];

          makeStartupEntry =
            entry:
            let
              workspaceCases = lib.concatStringsSep "\n" (
                lib.mapAttrsToList (count: workspace: ''
                  ${count}) workspace=${lib.escapeShellArg workspace} ;;
                '') entry.workspaceByMonitorCount
              );
            in
            pkgs.writeShellScript "startup-entry" ''
              monitor_count="$(${pkgs.hyprland}/bin/hyprctl -j monitors | ${pkgs.jq}/bin/jq 'length')"
              command=${lib.escapeShellArg (lib.escapeShellArgs entry.argv)}

              case "$monitor_count" in
              ${workspaceCases}
              *) workspace= ;;
              esac

              if [ -n "$workspace" ]; then
                  command="[workspace name:$workspace silent] $command"
              fi

              json_command="$(${pkgs.jq}/bin/jq -Rn --arg command "$command" '$command')"
              ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.exec_cmd($json_command)"
            '';
        in
        {
          systemd.user.services.startup-apps = lib.mkIf (user.startup != [ ]) {
            Unit = {
              Description = "Start desktop startup applications";
              After = [ "graphical-session.target" ] ++ dependencies;
              Wants = dependencies;
              PartOf = [ "graphical-session.target" ];
            };

            Service = {
              Type = "oneshot";
              ExecStart = map makeStartupEntry user.startup;
            };

            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
    })
  ];
}
