{
  den.aspects.system.base.core.nixos = {
    nix.settings = {
      accept-flake-config = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "raptor"
      ];
    };

    programs.nix-ld.enable = true;

    services = {
      envfs.enable = true;
      gvfs.enable = true;
      libinput.enable = true;
    };
  };
}
