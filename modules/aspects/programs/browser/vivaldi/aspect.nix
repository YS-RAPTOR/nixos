# TODO:  re extract all the preferences agian
{
  den.aspects.programs.browser.vivaldi.homeManager = { self', ... }: {
    home.packages = [ self'.packages.vivaldi-with-codecs ];
    xdg.configFile."vivaldi/custom-css/index.css".source = ./_files/index.css;
  };
}
