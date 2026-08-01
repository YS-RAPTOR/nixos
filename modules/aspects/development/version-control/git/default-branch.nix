{ den, ... }: {
  den.aspects.development.version-control.git.default-branch = {
    includes = [ den.aspects.development.version-control.git.client ];
    homeManager.programs.git.settings.init.defaultBranch = "main";
  };
}
