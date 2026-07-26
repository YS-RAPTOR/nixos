{
  den.aspects.tooling.android.homeManager = { pkgs, ... }: {
    home = {
      packages = [
        pkgs.android-studio
        pkgs.android-tools
      ];

      sessionVariables = {
        ANDROID_HOME = "$HOME/Android/Sdk";
        ANDROID_SDK_ROOT = "$HOME/Android/Sdk";
      };
    };
  };
}
