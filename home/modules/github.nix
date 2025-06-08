{ userSettings, ... }: {
  programs.git = {
    enable = true;
    userName = userSettings.github-username;
    userEmail = userSettings.email;

    extraConfig.credential.helper = "manager";
    extraConfig.credential."https://github.com".username = "YourUserName";
    extraConfig.credential.credentialStore = "gpg";
  };
}
