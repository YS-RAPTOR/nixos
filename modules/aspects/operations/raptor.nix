{
  den.aspects.operations.raptor.includes = [
    ({ host, user, ... }: {
      name = "raptor(${user.userName}@${host.name})";
      homeManager =
        { pkgs, ... }:
        let
          nixDirectory = "/home/${user.userName}/NixOS";
          raptor = pkgs.writeShellApplication {
            name = "raptor";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.curl
              pkgs.git
              pkgs.hyprland
              pkgs.jq
              pkgs.nh
              pkgs.nix
              pkgs.procps
              pkgs.systemd
            ];
            text = ''
              nix_directory=''${NIX_DIRECTORY:-${nixDirectory}}

              warn_extra_args() {
                  if [ "$#" -gt 1 ]; then
                      echo "Warning: The '$1' command has no subcommands (no $2 subcommand)"
                  fi
              }

              refresh() {
                  echo "Reloading Hyprland"
                  hyprctl reload >/dev/null
                  echo "Restarting Waybar"
                  systemctl --user restart waybar.service
                  echo "Restarting Hyprpaper"
                  systemctl --user restart hyprpaper.service
              }

              update() {
                  pushd "$nix_directory" >/dev/null
                  nix run .#write-flake
                  nix flake update
                  bash packages/update.sh
                  popd >/dev/null
              }

              pull() {
                  local stash_before stash_after stashed=false
                  stash_before=$(git -C "$nix_directory" rev-parse --verify refs/stash 2>/dev/null || true)
                  git -C "$nix_directory" stash push --include-untracked --message raptor-auto-stash
                  stash_after=$(git -C "$nix_directory" rev-parse --verify refs/stash 2>/dev/null || true)
                  [ "$stash_before" != "$stash_after" ] && stashed=true

                  if ! git -C "$nix_directory" pull; then
                      echo "Failed to pull from remote" >&2
                      $stashed && git -C "$nix_directory" stash pop || true
                      return 1
                  fi

                  if $stashed && ! git -C "$nix_directory" stash pop; then
                      echo "Failed to apply stashed changes - possible merge conflict" >&2
                      return 1
                  fi
              }

              collect_garbage() {
                  case "''${1:-}" in
                      full)
                          sudo nix-collect-garbage --delete-old
                          nix-collect-garbage --delete-old
                          ;;
                      "")
                          sudo nix-collect-garbage --delete-older-than 30d
                          nix-collect-garbage --delete-older-than 30d
                          ;;
                      *)
                          sudo nix-collect-garbage --delete-older-than "$1"
                          nix-collect-garbage --delete-older-than "$1"
                          ;;
                  esac
              }

              case "''${1:-}" in
                  boot)
                      warn_extra_args "$@"
                      nh os boot --hostname ${host.name} "$nix_directory"
                      ;;
                  sync)
                      warn_extra_args "$@"
                      nh os switch --hostname ${host.name} "$nix_directory"
                      refresh
                      ;;
                  refresh)
                      warn_extra_args "$@"
                      refresh
                      ;;
                  update)
                      warn_extra_args "$@"
                      update
                      ;;
                  upgrade)
                      warn_extra_args "$@"
                      update
                      nh os switch --hostname ${host.name} "$nix_directory"
                      refresh
                      ;;
                  pull)
                      warn_extra_args "$@"
                      pull
                      ;;
                  gc)
                      [ "$#" -gt 2 ] && echo "Warning: The 'gc' command only accepts one argument (full or duration)"
                      collect_garbage "''${2:-}"
                      ;;
                  *)
                      echo "Usage: raptor [boot | sync | refresh | update | upgrade | pull | gc [full|<duration>]]"
                      exit 1
                      ;;
              esac
            '';
          };
        in
        {
          home = {
            packages = [ raptor ];
            sessionVariables.NH_FLAKE = nixDirectory;
          };
        };
    })
  ];
}
