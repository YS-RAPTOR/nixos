{ den, ... }: {
  den.aspects.operations.auto-update.includes = [
    den.aspects.services.network
    ({ host, user, ... }: {
      name = "auto-update(${user.userName}@${host.name})";
      nixos =
        { pkgs, ... }:
        let
          stateDirectory = "nixos-updater";
          checkout = "/var/lib/${stateDirectory}/config";
          resultFile = "/var/lib/${stateDirectory}/result";
          repository = "https://github.com/YS-RAPTOR/NixOS.git";
        in
        {
          systemd.services = {
            nixos-update-prepare = {
              description = "Prepare the next NixOS update";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              path = [
                pkgs.bash
                pkgs.coreutils
                pkgs.curl
                pkgs.git
                pkgs.jq
                pkgs.nix
              ];
              environment = {
                GIT_CONFIG_GLOBAL = "/dev/null";
                GIT_CONFIG_SYSTEM = "/dev/null";
                HOME = "/home/${user.userName}";
              };
              serviceConfig = {
                Type = "oneshot";
                User = user.userName;
                StateDirectory = stateDirectory;
                StateDirectoryMode = "0750";
              };
              unitConfig.OnSuccess = "nixos-update-install.service";
              unitConfig.OnFailure = "nixos-update-failure.service";
              script = ''
                set -euo pipefail

                if [ ! -d ${checkout}/.git ]; then
                    rm -rf ${checkout}
                    git clone --no-checkout ${repository} ${checkout}
                fi

                git -C ${checkout} fetch --prune origin main
                git -C ${checkout} reset --hard origin/main
                git -C ${checkout} clean -fdx

                pushd ${checkout} >/dev/null
                nix run .#write-flake
                nix flake update
                bash packages/update.sh
                popd >/dev/null

                temporary=$(mktemp ${resultFile}.XXXXXX)
                trap 'rm -f "$temporary"' EXIT
                nix build \
                    "path:${checkout}#nixosConfigurations.${host.name}.config.system.build.toplevel" \
                    --no-link \
                    --print-out-paths >"$temporary"
                mv "$temporary" ${resultFile}
              '';
            };

            nixos-update-install = {
              description = "Install the prepared NixOS update for the next boot";
              after = [ "nixos-update-prepare.service" ];
              path = [
                pkgs.coreutils
                pkgs.libnotify
                pkgs.nix
                pkgs.util-linux
              ];
              serviceConfig.Type = "oneshot";
              unitConfig.OnFailure = "nixos-update-failure.service";
              script = ''
                set -euo pipefail

                result=$(<${resultFile})
                test -x "$result/bin/switch-to-configuration"
                nix-env --profile /nix/var/nix/profiles/system --set "$result"
                "$result/bin/switch-to-configuration" boot

                uid=$(id -u ${user.userName})
                if [ -S "/run/user/$uid/bus" ]; then
                    runuser -u ${user.userName} -- \
                        env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                        notify-send --app-name="NixOS Update" \
                        "NixOS Auto Update" \
                        "Update ready! Reboot or run 'raptor sync' to apply." || true
                fi
              '';
            };

            nixos-update-failure = {
              description = "Report a failed NixOS update";
              path = [
                pkgs.coreutils
                pkgs.libnotify
                pkgs.util-linux
              ];
              serviceConfig.Type = "oneshot";
              script = ''
                uid=$(id -u ${user.userName})
                if [ -S "/run/user/$uid/bus" ]; then
                    runuser -u ${user.userName} -- \
                        env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                        notify-send --urgency=critical --app-name="NixOS Update" \
                        "NixOS Auto Update Failed" \
                        "''${MONITOR_UNIT:-Automatic update} failed; inspect its systemd status." || true
                fi
              '';
            };
          };

          systemd.timers.nixos-update-prepare = {
            description = "Daily NixOS update timer";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "daily";
              RandomizedDelaySec = "30min";
              Persistent = true;
            };
          };
        };
    })
  ];
}
