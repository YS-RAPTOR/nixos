{
  users.users.raptor.uid = 1000;

  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/48533759077E6AFE";
    fsType = "ntfs-3g";
    options = [
      "rw"
      "uid=1000"
    ];
  };

  fileSystems."/mnt/games" = {
    device = "/dev/disk/by-uuid/F629EC8EEE63BDB5";
    fsType = "ntfs-3g";
    options = [
      "rw"
      "uid=1000"
    ];
  };
}
