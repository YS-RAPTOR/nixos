{ pkgs, userSettings, ... }:
let
  myScript = ''
    if [ "$1" = "sync" ]; then
      if [ "$#" = 1 ]; then
  '' + userSettings.nixDir + ''
    /sync.sh;
              exit 0;
            elif [ "$2" = "user" ]; then
  '' + userSettings.nixDir + ''
    /sync-user.sh;
              exit 0;
            elif [ "$2" = "system" ]; then
  '' + userSettings.nixDir + ''
    /sync-system.sh;
              exit 0;
            else
              echo "Please pass 'system' or 'user' if supplying a second argument"
            fi
          elif [ "$1" = "refresh" ]; then
            if [ "$#" -gt 1 ]; then
              echo "Warning: The 'refresh' command has no subcommands (no $2 subcommand)";
            fi
  '' + userSettings.nixDir + ''
    /sync-posthook.sh;
            exit 0;
          elif [ "$1" = "update" ]; then
            if [ "$#" -gt 1 ]; then
              echo "Warning: The 'update' command has no subcommands (no $2 subcommand)";
            fi
  '' + userSettings.nixDir + ''
    /update.sh;
            exit 0;
          elif [ "$1" = "upgrade" ]; then
            if [ "$#" -gt 1 ]; then
              echo "Warning: The 'update' command has no subcommands (no $2 subcommand)";
            fi
  '' + userSettings.nixDir + ''
    /upgrade.sh;
            exit 0;
          elif [ "$1" = "pull" ]; then
            if [ "$#" -gt 1 ]; then
              echo "Warning: The 'upgrade' command has no subcommands (no $2 subcommand)";
            fi
  '' + userSettings.nixDir + ''
    /pull.sh;
            exit 0;
          elif [ "$1" = "gc" ]; then
            if [ "$#" -gt 2 ]; then
              echo "Warning: The 'gc' command only accepts one argument (collect_older_than)";
            fi
            if [ "$2" = "full" ]; then
              sudo nix-collect-garbage --delete-old;
              nix-collect-garbage --delete-old;
            elif [ "$2" ]; then
              sudo nix-collect-garbage --delete-older-than $2;
              nix-collect-garbage --delete-older-than $2;
            else
              sudo nix-collect-garbage --delete-older-than 30d;
              nix-collect-garbage --delete-older-than 30d;
            fi
          fi
  '';
in { environment.systemPackages = [ (pkgs.writeScriptBin "raptor" myScript) ]; }
