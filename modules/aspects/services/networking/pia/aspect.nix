{ den, ... }: {
  den.batteries.services.networking.pia =
    {
      region,
      autoStart ? true,
      killSwitch ? true,
    }:
    {
      description = "Deploys the PIA WireGuard controller and desktop controls.";

      includes = [
        den.aspects.services.networking.networkmanager
        (
          { host, ... }:
          let
            clientUsers = map (user: user.userName) (builtins.attrValues host.users);
          in
          {
            name = "pia-wireguard@${host.name}";

            nixos =
              {
                lib,
                pkgs,
                self',
                ...
              }:
              let
                package = self'.packages.pia-vpn;
                serviceUser = "pia-vpn";
                controlGroup = "pia-vpn-control";
                stateDirectory = "pia-wireguard";
                runtimeDirectory = "pia-wireguard";
                credentialDirectory = "pia-wireguard-credentials";
                credentialPath = "/var/lib/${credentialDirectory}/pia-auth.cred";
                configPath = "/etc/pia-vpn/config.json";
                configFile = (pkgs.formats.json { }).generate "pia-vpn-config.json" {
                  default_region = region;
                  auto_start = autoStart;
                  kill_switch = killSwitch;
                  socket_group = controlGroup;
                  credential_path = credentialPath;
                  controller_unit = "pia-wireguard.service";
                };
                setupStatus = builtins.toJSON {
                  state = "setup-required";
                  desired = autoStart;
                  default_region = region;
                  effective_region = region;
                  interface = "pia";
                };
                cleanup = pkgs.writeShellScript "pia-wireguard-cleanup" ''
                  if [ "''${SERVICE_RESULT:-}" = success ]; then
                    ${lib.getExe' pkgs.wireguard-tools "wg-quick"} down /run/${runtimeDirectory}/pia.conf || true
                    ${lib.getExe pkgs.nftables} delete table inet pia_vpn || true
                    rm -f /run/${runtimeDirectory}/pia.conf
                  fi
                '';
              in
              {
                environment.etc."pia-vpn/config.json".source = configFile;
                environment.systemPackages = [ package ];

                networking = {
                  resolvconf.enable = true;
                  firewall.checkReversePath = "loose";
                };

                users = {
                  groups.${serviceUser} = { };
                  groups.${controlGroup}.members = clientUsers;
                  users.${serviceUser} = {
                    isSystemUser = true;
                    group = serviceUser;
                    description = "PIA WireGuard controller";
                  };
                };

                systemd.tmpfiles.rules = [
                  "d /var/lib/${stateDirectory} 0700 ${serviceUser} ${serviceUser} -"
                  "d /var/lib/${credentialDirectory} 0700 root root -"
                  "d /run/${runtimeDirectory} 0750 ${serviceUser} ${controlGroup} -"
                  "f /run/${runtimeDirectory}/status.json 0640 ${serviceUser} ${controlGroup} - ${setupStatus}"
                ];

                systemd.services.pia-wireguard = {
                  description = "Private Internet Access WireGuard controller";
                  wantedBy = [ "multi-user.target" ];
                  wants = [ "network-online.target" ];
                  after = [
                    "network-online.target"
                    "NetworkManager.service"
                  ];

                  unitConfig.ConditionPathExists = credentialPath;

                  path = [
                    pkgs.coreutils
                    pkgs.iproute2
                    pkgs.nftables
                    pkgs.openresolv
                    pkgs.procps
                    pkgs.systemd
                    pkgs.wireguard-tools
                  ];

                  environment.PYTHONUNBUFFERED = "1";

                  serviceConfig = {
                    Type = "simple";
                    User = serviceUser;
                    Group = controlGroup;
                    SupplementaryGroups = [ serviceUser ];
                    ExecStart = "${lib.getExe' package "pia-vpn-controller"} --config ${configPath}";
                    ExecStopPost = cleanup;
                    Restart = "on-failure";
                    RestartSec = "5s";
                    TimeoutStopSec = "20s";

                    StateDirectory = stateDirectory;
                    StateDirectoryMode = "0700";
                    RuntimeDirectory = runtimeDirectory;
                    RuntimeDirectoryMode = "0750";
                    LoadCredentialEncrypted = "pia-auth:${credentialPath}";

                    AmbientCapabilities = [
                      "CAP_DAC_OVERRIDE"
                      "CAP_NET_ADMIN"
                    ];
                    CapabilityBoundingSet = [
                      "CAP_DAC_OVERRIDE"
                      "CAP_NET_ADMIN"
                    ];
                    NoNewPrivileges = true;

                    LockPersonality = true;
                    MemoryDenyWriteExecute = true;
                    PrivateTmp = true;
                    ProtectClock = true;
                    ProtectControlGroups = true;
                    ProtectHome = true;
                    ProtectHostname = true;
                    ProtectKernelLogs = true;
                    ProtectKernelModules = true;
                    ProtectKernelTunables = false;
                    ProtectSystem = "strict";
                    ReadWritePaths = [ "-/run/resolvconf" ];
                    RestrictAddressFamilies = [
                      "AF_INET"
                      "AF_NETLINK"
                      "AF_UNIX"
                    ];
                    RestrictNamespaces = true;
                    RestrictRealtime = true;
                    SystemCallArchitectures = "native";
                    UMask = "0077";
                  };
                };

                security.polkit.enablePkexecWrapper = true;
                security.polkit.extraConfig = ''
                  polkit.addRule(function(action, subject) {
                    const helper = "${lib.getExe' package "pia-vpn-credential-helper"}";
                    const command = action.lookup("command_line");
                    if (action.id === "org.freedesktop.policykit.exec" &&
                        action.lookup("program") === helper &&
                        (command === helper + " set" || command === helper + " clear") &&
                        subject.active && subject.local && subject.isInGroup("wheel")) {
                      return polkit.Result.YES;
                    }
                  });
                '';
              };

            provides.to-users.includes = [ (den.batteries.desktop.shell.panel.waybar.pia { inherit region; }) ];
          }
        )
      ];
    };
}
