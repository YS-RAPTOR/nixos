{ den, ... }: {
  den.aspects.development.version-control.git.identity.includes = [
    den.aspects.development.version-control.git.client
    ({ user, ... }: {
      name = "git-identity(${user.userName})";

      homeManager = { lib, ... }: {
        assertions = [
          {
            assertion = user.git != null;
            message = "A Git identity must be configured for ${user.userName}.";
          }
        ];

        programs.git.settings.user = lib.mkIf (user.git != null) { inherit (user.git) name email; };
      };
    })
  ];
}
