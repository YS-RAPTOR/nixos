{ pkgs, ... }:
{
    stylix = {
        enable = true;
        base16Scheme = {
            base00 = "#16161E";
            base01 = "#1A1B26";
            base02 = "#2F3549";
            base03 = "#444B6A";
            base04 = "#787C99";
            base05 = "#787C99";
            base06 = "#CBCCD1";
            base07 = "#D5D6DB";
            base08 = "#F7768E";
            base09 = "#FF9E64";
            base0A = "#E0AF68";
            base0B = "#41A6B5";
            base0C = "#7DCFFF";
            base0D = "#7AA2F7";
            base0E = "#BB9AF7";
            base0F = "#D18616";
        };
        polarity = "dark";
        opacity.terminal = 0.1;

        fonts = {
            monospace = {
                package = pkgs.nerd-fonts.caskaydia-cove;
                name = "CaskaydiaCove Nerd Font Mono";
            };
        };

        # TODO: Figure out my own icon theme. Low Priority
        # MoreWaita extends Adwaita, so both packages are needed
        icons = {
            enable = true;
            package = pkgs.symlinkJoin {
                name = "morewaita-with-adwaita";
                paths = [
                    pkgs.morewaita-icon-theme
                    pkgs.adwaita-icon-theme
                ];
            };
            dark = "MoreWaita";
            light = "MoreWaita";
        };

        cursor =
            let
                getFrom = url: hash: name: {
                    size = 24;
                    name = name;
                    package = pkgs.runCommand "moveUp" { } ''
                        mkdir -p $out/share/icons
                        ln -s ${
                            builtins.fetchTarball {
                                url = url;
                                sha256 = hash;
                            }
                        } $out/share/icons/${name}
                    '';
                };
            in
            getFrom
                "https://github.com/ful1e5/notwaita-cursor/releases/download/v1.0.0-alpha1/Notwaita-White.tar.xz"
                "0p41q41cnwipd8lqd3dj0p9qjabp1pd5kdqy0k95nq31zhwqd4y7"
                "Notwaita-White";
    };

    fonts.packages = with pkgs; [
        hack-font
        inter
        corefonts
        vista-fonts
        wineWow64Packages.fonts
        google-fonts
    ];
}
