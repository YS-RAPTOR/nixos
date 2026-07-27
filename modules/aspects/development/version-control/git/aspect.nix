{ den, ... }: {
  den.aspects.development.version-control.git.includes = [
    den.aspects.development.version-control.git.client
    den.aspects.development.version-control.git.github-ssh
    den.aspects.development.version-control.git.identity
    den.aspects.development.version-control.github-cli
    den.aspects.development.version-control.git.lazygit
  ];
}
