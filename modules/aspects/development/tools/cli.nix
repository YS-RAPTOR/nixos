{
  den.aspects.development.tools.cli.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.fd
      pkgs.gnumake
      pkgs.jq
      pkgs.lsof
      pkgs.ripgrep
      pkgs.trash-cli
      pkgs.unzip
      pkgs.wget
    ];

    programs.btop.enable = true;
  };
}
