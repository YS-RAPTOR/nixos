{ userSettings, ... }: {
  programs.git = {
    programs.git.enable = true;
    programs.git.userName = userSettings.github-username;
    programs.git.userEmail = userSettings.email;
  };
}
