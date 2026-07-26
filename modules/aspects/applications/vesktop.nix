{
  den.aspects.applications.vesktop.homeManager = { pkgs, ... }: {
    home.packages = [ pkgs.vesktop ];
    xdg.mimeApps = {
      enable = true;
      defaultApplications."x-scheme-handler/discord" = "vesktop.desktop";
    };
  };
}
