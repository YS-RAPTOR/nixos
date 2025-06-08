{ pkgs, ... }: {
  fonts.packages = with pkgs; [
    corefonts
    vista-fonts
    nerd-fonts.caskaydia-cove
  ];
}
