{ den, ... }: {
  den.aspects.services.credentials.includes = [
    den.aspects.services.credentials.gnome-keyring
    den.aspects.services.credentials.gpg-agent
  ];
}
