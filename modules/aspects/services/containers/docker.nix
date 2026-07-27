{
  den.aspects.services.containers.docker.includes = [
    ({ user, host, ... }: {
      name = "docker(${user.userName}@${host.name})";

      nixos = {
        virtualisation.docker.enable = true;
        users.users.${user.userName}.extraGroups = [ "docker" ];
      };
    })
  ];
}
