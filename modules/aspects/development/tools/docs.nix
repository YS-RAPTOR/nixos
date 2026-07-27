{
  den.aspects.development.tools.docs.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.ghostscript
      pkgs.imagemagick
      pkgs.markdownlint-cli2
      pkgs.mermaid-cli
      pkgs.tectonic-unwrapped
    ];
  };
}
