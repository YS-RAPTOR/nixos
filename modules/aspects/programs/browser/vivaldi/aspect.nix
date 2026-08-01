# TODO:  re extract all the preferences agian
{
  den.aspects.programs.browser.vivaldi.homeManager = { pkgs, ... }: {
    home.packages = [ pkgs.vivaldi ];
    xdg.configFile."vivaldi/custom-css/index.css".source = ./_files/index.css;
  };
}
