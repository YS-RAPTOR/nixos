{
  den.aspects.programs.editor.neovim.homeManager = { pkgs, ... }: {
    programs.neovim = {
      enable = true;
      extraPackages = [
        pkgs.fd
        pkgs.git
        pkgs.ghostscript
        pkgs.imagemagick
        pkgs.markdownlint-cli2
        pkgs.nixfmt
        pkgs.prettier
        pkgs.ripgrep
        pkgs.shader-slang
        pkgs.typescript-go
        pkgs.wl-clipboard
        pkgs.zls
      ];
    };
    xdg.configFile."dictionary/words.txt".source = ./_files/dictionary/words.txt;
    xdg.configFile."nvim".source = ./_config;
  };
}
