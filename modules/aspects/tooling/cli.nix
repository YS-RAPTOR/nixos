{
  den.aspects.tooling.cli.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.fd
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
