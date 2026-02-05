{ settings, pkgs, lib, ... }:
let
  user = settings.user.username;
  nixDir = settings.user.nixDir;
  path = "${
      lib.makeBinPath [
        pkgs.git
        pkgs.nix
        pkgs.nixos-rebuild
        pkgs.coreutils
        pkgs.bash
        pkgs.dunst
      ]
    }:/run/current-system/sw/bin";
in {
  # Step 1: Pull and update flake (runs as user)
  systemd.services.nixos-auto-update-fetch = {
    description = "NixOS Auto Update - Fetch";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Environment = [
        "PATH=${path}"
        "HOME=/home/${user}"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
      ];
    };
    script = ''
      set -euo pipefail

      notify() {
        dunstify -a "NixOS Update" -u "$1" "NixOS Auto Update" "$2"
      }

      echo "Starting NixOS auto-update fetch at $(date)"

      echo "Pulling latest changes..."
      if ! raptor pull; then
        notify critical "Failed to pull from GitHub"
        exit 1
      fi

      echo "Updating flake inputs..."
      if ! raptor update; then
        notify critical "Failed to update flake inputs"
        exit 1
      fi

      echo "Fetch completed successfully at $(date)"
    '';
  };

  # Step 2: Build (runs as root, after fetch succeeds)
  systemd.services.nixos-auto-update-build = {
    description = "NixOS Auto Update - Build";
    after = [ "nixos-auto-update-fetch.service" ];
    requires = [ "nixos-auto-update-fetch.service" ];
    wantedBy = [ "nixos-auto-update-fetch.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = [ "PATH=${path}" "HOME=/root" ];
    };
    script = ''
      set -euo pipefail

      notify() {
        uid=$(id -u ${user})
        sudo -u ${user} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus dunstify -a "NixOS Update" -u "$1" "NixOS Auto Update" "$2"
      }

      # Allow nix to access user-owned git repo
      git config --global --add safe.directory "${nixDir}"

      echo "Building new configuration..."
      if ! nixos-rebuild boot --impure --flake "${nixDir}"; then
        notify critical "Failed to build new configuration"
        exit 1
      fi

      notify normal "Update ready! Reboot or run 'raptor sync' to apply."
      echo "Auto-update build completed successfully at $(date)"
    '';
  };

  # Timer triggers the fetch, which then triggers the build
  systemd.timers.nixos-auto-update-fetch = {
    description = "Timer for NixOS Flake Auto Update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
}
