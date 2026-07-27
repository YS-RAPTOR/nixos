# TODO: Rather than max value have startValue and if startValue is not defined then the keyboard brightness auto start is diabled
{
  den.batteries.system.hardware.brightness.keyboard = { device, maxValue }: {
    description = "Sets keyboard brightness at boot.";

    includes = [
      ({ host, ... }: {
        name = "keyboard-brightness@${host.name}";

        nixos =
          { lib, pkgs, ... }:
          let
            keyboardBrightness = pkgs.writeShellApplication {
              name = "keyboard-brightness";
              runtimeInputs = [ pkgs.brightnessctl ];
              text = ''
                case "''${1:-}" in
                    dim) brightnessctl -s -d ${lib.escapeShellArg device} set 0 ;;
                    restore) brightnessctl -r -d ${lib.escapeShellArg device} ;;
                    *)
                        echo "Usage: keyboard-brightness {dim|restore}" >&2
                        exit 2
                        ;;
                esac
              '';
            };

          in
          {
            environment.systemPackages = [ keyboardBrightness ];

            systemd.services.keyboard-brightness = {
              description = "Set keyboard brightness at boot";
              after = [ "basic.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${lib.getExe pkgs.brightnessctl} -d ${device} set ${toString maxValue}";
              };
            };
          };
      })
    ];
  };
}
