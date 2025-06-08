{ userSettings, ... }: {
  programs.git = {
    enable = true;
    userName = userSettings.github-username;
    userEmail = userSettings.email;
  };
}
