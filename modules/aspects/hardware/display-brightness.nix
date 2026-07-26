{
  den.batteries.display-brightness = backlights: {
    description = "Configures display brightness controls.";

    includes = [
      ({ host, ... }: {
        name = "display-brightness@${host.name}";

        nixos =
          { lib, pkgs, ... }:
          let
            displayBrightness = pkgs.writeShellApplication {
              name = "display-brightness";
              runtimeInputs = [ pkgs.brightnessctl ];
              text = ''
                devices=( ${lib.escapeShellArgs backlights} )

                for device in "''${devices[@]}"; do
                    case "''${1:-}" in
                        up) brightnessctl -e -d "$device" set 5%+ ;;
                        down) brightnessctl -e -d "$device" set 5%- ;;
                        dim) brightnessctl -s -d "$device" set 1% ;;
                        restore) brightnessctl -r -d "$device" ;;
                        *)
                            echo "Usage: display-brightness {up|down|dim|restore}" >&2
                            exit 2
                            ;;
                    esac
                done
              '';
            };
          in
          {
            environment.systemPackages = [ displayBrightness ];
          };
      })
    ];
  };
}
