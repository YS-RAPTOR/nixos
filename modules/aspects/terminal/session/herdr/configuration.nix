{ den, ... }: {
  den.aspects.terminal.session.herdr.configuration = {
    includes = [ den.aspects.appearance.theme.stylix ];

    homeManager =
      {
        config,
        lib,
        pkgs,
        self',
        ...
      }:
      let
        colors = config.lib.stylix.colors;
        herdr = self'.packages.herdr;
        herdrContext = pkgs.callPackage ./_scripts/package.nix { };
        toml = pkgs.formats.toml { };
      in
      {
        home.packages = [ herdr ];

        xdg.configFile."herdr/config.toml".source = toml.generate "herdr-config.toml" {
          onboarding = false;

          experimental.kitty_graphics = true;

          theme = {
            name = "terminal";
            custom = {
              accent = "#${colors.base0D}";
              panel_bg = "reset";
              surface0 = "#${colors.base01}";
              surface1 = "#${colors.base02}";
              surface_dim = "#${colors.base00}";
              overlay0 = "#${colors.base03}";
              overlay1 = "#${colors.base04}";
              text = "#${colors.base06}";
              subtext0 = "#${colors.base04}";
              mauve = "#${colors.base0E}";
              green = "#${colors.base0B}";
              yellow = "#${colors.base0A}";
              red = "#${colors.base08}";
              blue = "#${colors.base0D}";
              teal = "#${colors.base0C}";
              peach = "#${colors.base09}";
            };
          };

          ui = {
            accent = "#${colors.base0D}";
            prompt_new_tab_name = false;
            sidebar_start_collapsed = true;
            toast = {
              delivery = "system";
              delay_seconds = 1;
              clipboard.enabled = false;
            };
          };

          keys = {
            prefix = "ctrl+space";

            help = "prefix+?";
            settings = "prefix+s";
            detach = "prefix+q";
            reload_config = "prefix+f5";
            open_notification_target = "prefix+o";
            goto = "prefix+g";
            toggle_sidebar = "prefix+e";

            new_tab = "prefix+n";
            rename_tab = "";
            previous_tab = "prefix+h";
            next_tab = "prefix+l";
            switch_tab = "prefix+1..9";
            close_tab = "prefix+x";

            workspace_picker = "prefix+c";
            new_workspace = "prefix+shift+n";
            rename_workspace = "";
            close_workspace = "prefix+shift+x";
            previous_workspace = "prefix+shift+h";
            next_workspace = "prefix+shift+l";
            switch_workspace = "prefix+shift+1..9";
            new_worktree = "prefix+shift+g";
            open_worktree = "prefix+shift+o";
            remove_worktree = "prefix+shift+d";
            navigate_workspace_up = "shift+k";
            navigate_workspace_down = "shift+j";

            previous_agent = "prefix+ctrl+h";
            next_agent = "prefix+ctrl+l";
            focus_agent = "prefix+ctrl+1..9";

            rename_pane = "";
            close_pane = "prefix+alt+x";
            focus_pane_left = "prefix+alt+h";
            focus_pane_down = "prefix+alt+j";
            focus_pane_up = "prefix+alt+k";
            focus_pane_right = "prefix+alt+l";
            swap_pane_left = "prefix+alt+shift+h";
            swap_pane_down = "prefix+alt+shift+j";
            swap_pane_up = "prefix+alt+shift+k";
            swap_pane_right = "prefix+alt+shift+l";
            last_pane = "prefix+alt+p";
            resize_mode = "prefix+alt+shift+r";

            copy_mode = "prefix+v";
            edit_scrollback = "prefix+shift+e";
            zoom = "prefix+z";
            cycle_pane_next = "prefix+tab";
            cycle_pane_previous = "prefix+shift+tab";
            split_vertical = "";
            split_horizontal = "";

            navigate_pane_left = "h";
            navigate_pane_down = "j";
            navigate_pane_up = "k";
            navigate_pane_right = "l";

            remote_image_paste = "ctrl+alt+v";

            command = [
              {
                key = "ctrl+/";
                command = "${lib.getExe herdrContext} focus editor";
                type = "shell";
                description = "Toggle between the current directory's editor and shell tabs";
              }
              {
                key = "ctrl+.";
                command = "${lib.getExe herdrContext} focus agent";
                type = "shell";
                description = "Toggle between the current directory's agent and shell tabs";
              }
            ];
          };
        };
      };
  };
}
