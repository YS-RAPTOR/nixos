{ den, inputs, ... }: {
  den.aspects.development.computer-use.vivaldi-golden.includes = [
    ({ user, ... }: {
      name = "vivaldi-golden(${user.userName})";

      nixos =
        { lib, pkgs, ... }:
        let
          home = "/home/${user.userName}";
          source = "${home}/.config/vivaldi";
          destination = "${home}/.local/state/agent-desktop/browser-golden/vivaldi";
          cloneProfile = pkgs.writeShellApplication {
            name = "clone-vivaldi-golden-${user.userName}";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.rsync
            ];
            text = ''
              source=${lib.escapeShellArg source}
              destination=${lib.escapeShellArg destination}
              ready="$destination/.agent-desktop-ready"

              install -d -m 0700 "$destination"

              rm -f "$ready"
              if [ -d "$source" ]; then
                rsync -a --delete --delete-excluded --delay-updates \
                  --exclude='/SingletonLock' \
                  --exclude='/SingletonSocket' \
                  --exclude='/SingletonCookie' \
                  --exclude='/DevToolsActivePort' \
                  --exclude='/Crash Reports/' \
                  "$source/" "$destination/"
              else
                rm -rf "$destination"
                install -d -m 0700 "$destination"
              fi

              rm -f \
                "$destination/SingletonLock" \
                "$destination/SingletonSocket" \
                "$destination/SingletonCookie" \
                "$destination/DevToolsActivePort"
              touch "$ready"
              chmod 0600 "$ready"
            '';
          };
        in
        {
          systemd.services."agent-desktop-vivaldi-golden-${user.userName}" = {
            description = "Refresh ${user.userName}'s golden Vivaldi profile before graphical login";
            after = [ "local-fs.target" ];
            before = [ "display-manager.service" ];
            requiredBy = [ "display-manager.service" ];

            serviceConfig = {
              Type = "oneshot";
              User = user.userName;
              Group = "users";
              ExecStart = lib.getExe cloneProfile;
              UMask = "0077";
              Nice = 10;
              IOSchedulingClass = "idle";
              IOSchedulingPriority = 7;
            };
          };
        };
    })
  ];

  den.aspects.development.computer-use.agent-desktop.includes = [ den.aspects.development.computer-use.vivaldi-golden ];

  den.aspects.development.computer-use.agent-desktop.homeManager =
    {
      config,
      lib,
      osConfig,
      pkgs,
      self',
      ...
    }:
    let
      package = self'.packages.agent-desktop;
      cuaDriver = self'.packages.cua-driver;
      configPath = "${config.xdg.configHome}/agent-desktop/config.json";
      configFile = (pkgs.formats.json { }).generate "agent-desktop-config.json" {
        state_root = "${config.xdg.stateHome}/agent-desktop";
        portal_service_dir = "${pkgs.xdg-desktop-portal}/share/dbus-1/services";
        host_dbus_address = "unix:path=/run/user/${toString osConfig.users.users.${config.home.username}.uid}/bus";
        novnc_web_root = "${pkgs.novnc}/share/webapps/novnc";
        vivaldi_golden_profile = "${config.xdg.stateHome}/agent-desktop/browser-golden/vivaldi";
        xdg_data_dirs = [
          "${pkgs.xdg-desktop-portal-wlr}/share"
          "${pkgs.xdg-desktop-portal-gtk}/share"
          "${pkgs.xdg-desktop-portal}/share"
        ];
        commands = {
          dbus = lib.getExe' pkgs.dbus "dbus-daemon";
          sway = lib.getExe pkgs.sway;
          swaymsg = lib.getExe' pkgs.sway "swaymsg";
          at_spi_launcher = "${pkgs.at-spi2-core}/libexec/at-spi-bus-launcher";
          at_spi_registry = "${pkgs.at-spi2-core}/libexec/at-spi2-registryd";
          pipewire = lib.getExe' pkgs.pipewire "pipewire";
          pw_dump = lib.getExe' pkgs.pipewire "pw-dump";
          wireplumber = lib.getExe' pkgs.wireplumber "wireplumber";
          portal_wlr = "${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr";
          portal_gtk = "${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk";
          portal = "${pkgs.xdg-desktop-portal}/libexec/xdg-desktop-portal";
          busctl = lib.getExe' pkgs.systemd "busctl";
          cua = lib.getExe cuaDriver;
          systemctl = lib.getExe' pkgs.systemd "systemctl";
          systemd_run = lib.getExe' pkgs.systemd "systemd-run";
          session = lib.getExe' package "agent-desktop-session";
          wayvnc = lib.getExe pkgs.wayvnc;
          vivaldi = lib.getExe pkgs.vivaldi;
          xdg_open = lib.getExe' pkgs.xdg-utils "xdg-open";
          fuse_overlayfs = lib.getExe pkgs.fuse-overlayfs;
          fusermount = "/run/wrappers/bin/fusermount3";
          cleanup = lib.getExe' package "agent-desktop-cleanup";
          secret_bridge = lib.getExe' package "agent-desktop-secret-bridge";
        };
      };
    in
    {
      home.packages = [ package ];
      home.sessionVariables.AGENT_DESKTOP_CONFIG = configPath;
      xdg.configFile."agent-desktop/config.json".source = configFile;

      systemd.user.services.agent-desktop-viewer = {
        Unit.Description = "Agent desktop noVNC viewer";
        Service = {
          Type = "simple";
          ExecStart = "${lib.getExe' package "agent-desktop-viewer"} --config ${configFile}";
          Restart = "on-failure";
          RestartSec = "2s";
          RuntimeDirectory = "agent-desktop-viewer";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectControlGroups = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
        };
      };
    };
}
