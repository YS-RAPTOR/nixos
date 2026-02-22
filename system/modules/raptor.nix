{ pkgs, settings, ... }:
let
    myScript = ''
        #!${pkgs.bash}/bin/sh

        NIX_DIR=${settings.user.nixDir};

        warn_extra_args() {
          [ "$#" -gt 1 ] && echo "Warning: The '$1' command has no subcommands (no $2 subcommand)"
        }

        refresh() {
          pgrep Hyprland &>/dev/null && echo "Reloading hyprland" && hyprctl reload &>/dev/null
          pgrep hyprpaper &>/dev/null && echo "Reapplying background via hyprpaper" && pkill hyprpaper && echo "Running hyprpaper" && hyprpaper &>/dev/null & disown
        }

        do_boot() {
          sudo nixos-rebuild boot --impure --flake "$NIX_DIR"
        }

        do_sync() {
          sudo nixos-rebuild switch --impure --flake "$NIX_DIR"
        }

        do_update() {
          pushd "$NIX_DIR" &>/dev/null
          nix flake update
          local ret=$?
          popd &>/dev/null
          return $ret
        }

        do_pull() {
          pushd "$NIX_DIR" &>/dev/null
          git stash
          git pull || { echo "Failed to pull from remote"; git stash pop; popd &>/dev/null; return 1; }
          git stash pop || { echo "Failed to apply stashed changes - possible merge conflict"; popd &>/dev/null; return 1; }
          popd &>/dev/null
        }

        do_gc() {
          [ "$#" -gt 1 ] && echo "Warning: The 'gc' command only accepts one argument (collect_older_than)"
          case "$1" in
            full) sudo nix-collect-garbage --delete-old && nix-collect-garbage --delete-old ;;
            "")   sudo nix-collect-garbage --delete-older-than 30d && nix-collect-garbage --delete-older-than 30d ;;
            *)    sudo nix-collect-garbage --delete-older-than "$1" && nix-collect-garbage --delete-older-than "$1" ;;
          esac
        }

        case "$1" in
          boot)    warn_extra_args "$@"; do_boot; exit $? ;;
          sync)    warn_extra_args "$@"; do_sync && refresh; exit $? ;;
          refresh) warn_extra_args "$@"; refresh; exit $? ;;
          update)  warn_extra_args "$@"; do_update; exit $? ;;
          upgrade) warn_extra_args "$@"; do_update && do_sync && refresh; exit $? ;;
          pull)    warn_extra_args "$@"; do_pull; exit $? ;;
          gc)      do_gc "$2"; exit $? ;;
          *)
            echo "Usage: $0 [boot | sync | refresh | update | upgrade | pull | gc [full|<duration>]]"
            exit 1
            ;;
        esac
    '';
in
{
    environment.systemPackages = [ (pkgs.writeScriptBin "raptor" myScript) ];
}
