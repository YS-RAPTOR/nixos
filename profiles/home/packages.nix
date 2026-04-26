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
            extra.affinity

        ]
        ++ packages.home {
            pkgs = pkgs;
            pkgs-stable = pkgs-stable;
            extra = extra;
        };
}
