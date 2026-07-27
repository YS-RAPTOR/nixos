{
  den.aspects.system.accounts.user.includes = [
    ({ user, ... }: {
      name = "system-user(${user.userName})";
      nixos.users.users.${user.userName}.description = user.userName;
    })
  ];
}
