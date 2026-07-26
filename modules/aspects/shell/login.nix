{ den, ... }: {
  den.aspects.shell.login = {
    includes = [ den.aspects.shell.stylix ];
    nixos =
      { pkgs, ... }:
      let
        pixelSakura = pkgs.runCommand "pixel-sakura.gif" { } ''
          cp ${pkgs.sddm-astronaut}/share/sddm/themes/sddm-astronaut-theme/Backgrounds/pixel_sakura.gif "$out"
        '';
      in
      {
        services.accounts-daemon.enable = true;

        programs.regreet = {
          enable = true;

          settings = {
            skip_selection = true;

            background = {
              path = pixelSakura;
              fit = "Cover";
            };

            appearance.greeting_msg = "Welcome back!";

            widget.clock = {
              format = "%H:%M%n%A, %d %B %Y";
              resolution = "1s";
            };
          };
        };

        stylix.targets.regreet.image.enable = false;
      };
  };
}
