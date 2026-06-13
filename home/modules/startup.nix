{
    lib,
    pkgs,
    settings,
    ...
}:
let
    services = [
        "pipewire.service"
        "wireplumber.service"
        "xdg-desktop-portal.service"
        "xdg-desktop-portal-hyprland.service"
        "xdg-desktop-portal-gtk.service"
    ];

    startupEntry =
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
            command=${lib.escapeShellArg entry.command}

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
    systemd.user.services.startup-apps = lib.mkIf (settings.startup != [ ]) {
        Unit = {
            Description = "Start desktop startup applications";
            After = [ "graphical-session.target" ] ++ services;
            Wants = services;
            PartOf = [ "graphical-session.target" ];
        };

        Service = {
            Type = "oneshot";
            ExecStart = map startupEntry settings.startup;
        };

        Install.WantedBy = [ "graphical-session.target" ];
    };
}
