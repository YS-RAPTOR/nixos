{ ... }:
let
  notwaita = builtins.fetchTarball {
    url =
      "https://github.com/ful1e5/notwaita-cursor/releases/download/v1.0.0-alpha1/Notwaita-White.tar.xz";
    sha256 = "0p41q41cnwipd8lqd3dj0p9qjabp1pd5kdqy0k95nq31zhwqd4y7";
  };
in {
  home.file.".icons/Notwaita-White".source = "${notwaita}";

}
