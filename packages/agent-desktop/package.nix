{
  at-spi2-core,
  coreutils,
  dbus,
  fuse-overlayfs,
  fuse3,
  lib,
  pipewire,
  python3Packages,
  sway,
  systemd,
  util-linux,
  wayvnc,
  wireplumber,
  wtype,
  xdg-utils,
  xdg-desktop-portal,
  xdg-desktop-portal-gtk,
  xdg-desktop-portal-wlr,
}:
python3Packages.buildPythonApplication {
  pname = "agent-desktop";
  version = "0.2.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./uv.lock
      # Activated-system E2E tests live in ./e2e and are deliberately absent
      # from the package source and pytestCheckHook.
      (lib.fileset.fileFilter (file: file.hasExt "py" || file.hasExt "html" || file.hasExt "js" || file.hasExt "css") ./src)
      (lib.fileset.fileFilter (file: file.hasExt "py") ./tests)
    ];
  };

  build-system = [ python3Packages.uv-build ];
  dependencies = with python3Packages; [
    aiohttp
    click
    dbus-next
    pydantic
  ];

  makeWrapperArgs = [
    "--prefix PATH : ${
      lib.makeBinPath [
        at-spi2-core
        coreutils
        dbus
        fuse-overlayfs
        fuse3
        pipewire
        sway
        systemd
        util-linux
        wayvnc
        wireplumber
        wtype
        xdg-utils
        xdg-desktop-portal
        xdg-desktop-portal-gtk
        xdg-desktop-portal-wlr
      ]
    }"
  ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  pythonImportsCheck = [ "agent_desktop" ];

  meta = {
    description = "On-demand private graphical desktops for computer-use agents";
    homepage = "https://github.com/YS-RAPTOR/NixOS";
    license = lib.licenses.mit;
    mainProgram = "agent-desktop";
    platforms = lib.platforms.linux;
  };
}
