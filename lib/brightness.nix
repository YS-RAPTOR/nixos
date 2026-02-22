{ settings }:
let
    backlights = settings.hardware.backlights;
in
{
    set =
        action:
        builtins.concatStringsSep " && " (map (dev: "brightnessctl -e -d ${dev} set ${action}") backlights);

    save =
        action:
        builtins.concatStringsSep " && " (map (dev: "brightnessctl -sd ${dev} set ${action}") backlights);

    restore = builtins.concatStringsSep " && " (map (dev: "brightnessctl -rd ${dev}") backlights);
}
