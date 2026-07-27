{ den, ... }: {
  den.batteries.programs.editor.defaults = {
    neovim = {
      includes = [ den.aspects.programs.editor.neovim ];
      homeManager.home.sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };
    };

    vscode = {
      includes = [ den.aspects.programs.editor.vscode ];
      homeManager.home.sessionVariables = {
        EDITOR = "code --wait";
        VISUAL = "code --wait";
      };
    };
  };
}
