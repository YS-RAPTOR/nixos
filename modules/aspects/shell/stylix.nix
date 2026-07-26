{ inputs, ... }: {
  den.aspects.shell.stylix.includes = [
    ({ host, ... }: {
      name = "stylix(${host.name})";

      nixos = { pkgs, ... }: {
        imports = [ inputs.stylix.nixosModules.stylix ];

        stylix = {
          enable = true;
          polarity = "dark";

          base16Scheme = {
            base00 = "16161E";
            base01 = "1A1B26";
            base02 = "2F3549";
            base03 = "444B6A";
            base04 = "787C99";
            base05 = "787C99";
            base06 = "CBCCD1";
            base07 = "D5D6DB";
            base08 = "F7768E";
            base09 = "FF9E64";
            base0A = "E0AF68";
            base0B = "41A6B5";
            base0C = "7DCFFF";
            base0D = "7AA2F7";
            base0E = "BB9AF7";
            base0F = "D18616";
          };

          opacity.terminal = 0.1;

          fonts.monospace = {
            package = pkgs.nerd-fonts.caskaydia-cove;
            name = "CaskaydiaCove Nerd Font Mono";
          };

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

          cursor = {
            size = 24;
            name = "Notwaita-White";
            package = pkgs.runCommand "notwaita-white" { } ''
              mkdir -p "$out/share/icons"
              ln -s ${
                pkgs.fetchzip {
                  url = "https://github.com/ful1e5/notwaita-cursor/releases/download/v1.0.0-alpha1/Notwaita-White.tar.xz";
                  hash = "sha256-x5OGOfxhYFvSBB63WdoNdymJ0wWyjYYpajdyywLBgVw=";
                  stripRoot = false;
                }
              } "$out/share/icons/Notwaita-White"
            '';
          };
        };

        fonts.packages = [
          pkgs.hack-font
          pkgs.inter
          pkgs.corefonts
          pkgs.vista-fonts
          pkgs.wineWow64Packages.fonts
          pkgs.google-fonts
        ];
      };

      homeManager.home.pointerCursor.enable = true;
    })
  ];
}
