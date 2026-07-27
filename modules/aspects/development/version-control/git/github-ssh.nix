{ den, ... }: {
  den.aspects.development.version-control.git.github-ssh = {
    includes = [ den.aspects.development.version-control.git.client ];
    homeManager.programs.git.settings.url."git@github.com:".insteadOf = "https://github.com/";
  };
}
