{ den, ... }: {
  den.aspects.desktop.session.lock.hyprlock = {
    includes = [ den.aspects.appearance.theme.stylix ];
    nixos.security.pam.services.hyprlock = { };

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        stylix.targets.hyprlock.image.enable = false;

        programs.hyprlock = {
          enable = true;
          settings = {
            general.hide_cursor = false;

            animations = {
              enabled = true;
              bezier = "linear, 1, 1, 0, 0";
              animation = [
                "fadeIn, 1, 5, linear"
                "fadeOut, 1, 5, linear"
                "inputFieldDots, 1, 2, linear"
              ];
            };

            background = {
              monitor = "";
              path = "screenshot";
              blur_passes = 3;
            };

            input-field = {
              monitor = "";
              size = "20%, 5%";
              outline_thickness = 3;
              outer_color = lib.mkForce "rgb(${config.lib.stylix.colors.base0B})";
              fade_on_empty = false;
              rounding = 15;
              font_family = "monospace";
              placeholder_text = "Input password...";
              fail_text = "$PAMFAIL";
              dots_spacing = 0.3;
              position = "0, -20";
              halign = "center";
              valign = "center";
            };

            label = [
              {
                monitor = "";
                text = "$TIME";
                font_size = 90;
                font_family = "monospace";
                position = "-30, 0";
                halign = "right";
                valign = "top";
              }
              {
                monitor = "";
                text = ''cmd[update:60000] ${lib.getExe' pkgs.coreutils "date"} +"%A, %d %B %Y"'';
                font_size = 25;
                font_family = "monospace";
                position = "-30, -150";
                halign = "right";
                valign = "top";
              }
            ];
          };
        };
      };
  };
}
