{
  den.aspects.tooling.git.includes = [
    ({ user, ... }: {
      name = "git(${user.userName})";

      homeManager = { self', ... }: {
        home.packages = [ self'.packages.gh ];

        programs = {
          git = {
            enable = true;
            settings = {
              user = {
                name = user.user.name;
                email = user.user.email;
              };
              url."git@github.com:".insteadOf = "https://github.com/";
            };
          };
          lazygit.enable = true;
        };
      };
    })
  ];
}
