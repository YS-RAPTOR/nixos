{
  den.aspects.system.core.nixos = {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    programs.nix-ld.enable = true;

    services = {
      envfs.enable = true;
      gvfs.enable = true;
      libinput.enable = true;
    };
  };
}
