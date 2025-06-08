{ userSettings, ... }: {
  programs.oh-my-posh = {
    enable = true;
    enableFishIntegration = true;
    settings = builtins.fromJSON (builtins.unsafeDiscardStringContext
      (builtins.readFile "${userSettings.homeDir}/themes/raptor.omp.json"));
  };
}
