{
  at-spi2-core,
  coreutils,
  dbus,
  fuse-overlayfs,
  fuse3,
  lib,
  pipewire,
  procps,
  python3Packages,
  sway,
  systemd,
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
  version = "0.1.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./uv.lock
      ./src/agent_desktop/__init__.py
      ./src/agent_desktop/browser.py
      ./src/agent_desktop/cli.py
      ./src/agent_desktop/cleanup.py
      ./src/agent_desktop/control.py
      ./src/agent_desktop/desktop_bus.py
      ./src/agent_desktop/errors.py
      ./src/agent_desktop/models.py
      ./src/agent_desktop/processes.py
      ./src/agent_desktop/runtime.py
      ./src/agent_desktop/session.py
      ./src/agent_desktop/secret_bridge.py
      ./src/agent_desktop/storage.py
      ./src/agent_desktop/system.py
      ./src/agent_desktop/systemd.py
      ./src/agent_desktop/viewer.py
      ./src/agent_desktop/assets/index.html
      ./src/agent_desktop/assets/app.js
      ./src/agent_desktop/assets/style.css
      ./tests/test_manager.py
      ./tests/test_models.py
      ./tests/test_runtime_layout.py
      ./tests/test_state_safety.py
      ./tests/test_viewer.py
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
        procps
        sway
        systemd
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
