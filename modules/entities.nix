{
  den.hosts.x86_64-linux.raptor-home-laptop = {
    users.raptor = {
      git = {
        name = "YS-RAPTOR";
        email = "yashan.sumanaratne@gmail.com";
      };
      wallpaper = ./users/raptor/_files/wallpaper.png;
    };
  };

  den.hosts.x86_64-linux.raptor-work-laptop = {
    users.yashan = {
      git = {
        name = "yashan-sumanaratne";
        email = "yashan.sumanaratne@oolio.com";
      };
      wallpaper = ./users/yashan/_files/wallpaper.jpg;
      startup = [
        {
          argv = [ "vivaldi" ];
          workspaceByMonitorCount = {
            "1" = "3";
            "2" = "A-1";
            "3" = "C-1";
          };
        }
        {
          argv = [ "slack" ];
          workspaceByMonitorCount = {
            "1" = "3";
            "2" = "A-2";
            "3" = "C-2";
          };
        }
        {
          argv = [ "teams-for-linux" ];
          workspaceByMonitorCount = {
            "1" = "3";
            "2" = "A-3";
            "3" = "C-3";
          };
        }
      ];
    };
  };
}
