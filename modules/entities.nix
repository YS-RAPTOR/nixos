{
  den.hosts.x86_64-linux.raptor-home-laptop = {
    users.raptor = {
      user = {
        name = "Yashan";
        email = "yashan.sumanaratne@gmail.com";
      };
      git.username = "YS-RAPTOR";
      wallpaper = ./users/raptor/_files/wallpaper.png;
    };
  };

  den.hosts.x86_64-linux.raptor-work-laptop = {
    users.yashan = {
      user = {
        name = "Yashan";
        email = "yashan.sumanaratne@oolio.com";
      };
      git.username = "yashan-sumanaratne";
      wallpaper = ./users/yashan/_files/wallpaper.jpg;
      startup = [
        {
          argv = [ "vivaldi" ];
          workspaceByMonitorCount = {
            "1" = "N-3";
            "2" = "A-1";
            "3" = "C-1";
          };
        }
        {
          argv = [ "slack" ];
          workspaceByMonitorCount = {
            "1" = "N-3";
            "2" = "A-2";
            "3" = "C-2";
          };
        }
        {
          argv = [ "teams-for-linux" ];
          workspaceByMonitorCount = {
            "1" = "N-3";
            "2" = "A-3";
            "3" = "C-3";
          };
        }
      ];
    };
  };
}
