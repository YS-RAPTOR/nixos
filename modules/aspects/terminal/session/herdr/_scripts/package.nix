{ buildGoModule, lib }:
buildGoModule {
  pname = "herdr-context";
  version = "0.1.0";
  src = ./.;
  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Semantic tab context, labels, and navigation for Herdr";
    mainProgram = "herdr-context";
    platforms = lib.platforms.linux;
  };
}
