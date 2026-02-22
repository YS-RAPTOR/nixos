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
            pkgs.slack
            pkgs.teams-for-linux
            pkgs.mailspring
            pkgs.tilt
            pkgs-stable.swift
            pkgs.kotlin
            extra.wombat

        ]
        ++ packages.home {
            pkgs = pkgs;
            pkgs-stable = pkgs-stable;
        };
}
