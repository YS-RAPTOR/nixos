let
    common = import ../common.nix;
    packages = common.packages;
in
{
    system =
        { pkgs, pkgs-stable }:
        [

        ]
        ++ packages.system {
            pkgs = pkgs;
            pkgs-stable = pkgs-stable;
        };

    home =
        {
            pkgs,
            pkgs-stable,
            extra,
        }:
        [
            pkgs.vesktop
            pkgs.codex
            pkgs.openvpn
            pkgs.openvpn3
            extra.affinity

        ]
        ++ packages.home {
            pkgs = pkgs;
            pkgs-stable = pkgs-stable;
            extra = extra;
        };
}
